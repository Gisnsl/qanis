/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:core';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:qanis/network/util/cert/pkcs12.dart';
import 'package:qanis/network/util/cert/x509.dart';
import 'package:qanis/network/util/logger.dart';
import 'package:qanis/network/util/random.dart';
import 'package:qanis/utils/lang.dart';

import 'cache.dart';
import 'cert/basic_constraints.dart';
import 'cert/cert_data.dart';
import 'cert/extension.dart';
import 'cert/key_usage.dart';
import 'crypto.dart';

Future<void> main() async {
  await CertificateManager.getCertificateContext('www.jianshu.com');
}

enum StartState { uninitialized, initializing, initialized }

class CertificateManager {
  /// 证书缓存
  static final ExpiringCache<String, SecurityContext> _certificateMap =
      ExpiringCache<String, SecurityContext>(const Duration(minutes: 30));

  /// 远程服务器真实证书缓存(ssl验证失败时拉取, 用于生成更贴近真实证书的叶子证书)
  static final ExpiringCache<String, X509CertificateData> _remoteCertMap =
      ExpiringCache<String, X509CertificateData>(const Duration(minutes: 15));

  /// 服务端密钥
  static AsymmetricKeyPair _serverKeyPair = CryptoUtils.generateRSAKeyPair();

  /// ca证书
  static X509CertificateData? _caCert;

  /// CA 证书 PEM 原文, 用于把根证书一起发给客户端
  static String? _caPem;

  /// ca私钥
  static late RSAPrivateKey _caPriKey;

  /// ca证书 subject DN 的原始 ASN.1 字节, 用作签发叶子证书的 issuer, 保证与 CA 二进制精确匹配
  static Uint8List? _caSubjectDnBytes;

  /// 是否初始化
  static StartState _state = StartState.uninitialized;
  static Completer<void> _initializationCompleter = Completer<void>();

  static SecurityContext? get(String host) {
    return _certificateMap[host];
  }

  static X509CertificateData? get caCert => _caCert;

  /// 清除缓存
  static void cleanCache() {
    _certificateMap.clear();
    _remoteCertMap.clear();
  }

  /// 获取域名自签名证书
  static Future<SecurityContext> getCertificateContext(String host) async {
    SecurityContext? securityContext = _certificateMap[host];
    if (securityContext != null) {
      return securityContext;
    }

    if (_state != StartState.initialized) {
      await initCAConfig();
    }

    return _createSecurityContext(host, remoteCert: _remoteCertMap[host]);
  }

  /// ssl验证失败时, 根据远程服务器真实证书重新生成叶子证书并刷新缓存
  ///
  /// [host] 域名
  /// [peerCertificate] 远程服务器证书(来自 [SecureSocket.peerCertificate])
  ///
  /// 返回 true 表示成功拉取并刷新了证书缓存; 若已经针对该域名拉取过, 或解析失败, 返回 false
  static Future<bool> generateByRemoteCert(String host, X509Certificate? peerCertificate) async {
    if (peerCertificate == null) {
      return false;
    }

    //同一域名只拉取一次, 避免重连风暴
    if (_remoteCertMap.containsKey(host)) {
      return false;
    }

    try {
      var remoteCert = X509Utils.x509CertificateFromPem(peerCertificate.pem);
      _remoteCertMap[host] = remoteCert;

      if (_state != StartState.initialized) {
        await initCAConfig();
      }

      _createSecurityContext(host, remoteCert: remoteCert);
      logger.d('regenerate certificate by remote cert for $host');
      return true;
    } catch (e, t) {
      logger.e('generate certificate by remote cert error: $host', error: e, stackTrace: t);
      return false;
    }
  }

  /// 生成域名叶子证书的 [SecurityContext] 并写入缓存
  static SecurityContext _createSecurityContext(String host, {X509CertificateData? remoteCert}) {
    String cer = generate(_caCert!, _serverKeyPair.publicKey as RSAPublicKey, _caPriKey, host, remoteCert: remoteCert);
    var rsaPrivateKey = _serverKeyPair.privateKey as RSAPrivateKey;

    // 叶子证书 + 根证书一起下发, 严格校验的客户端(如部分原生库)要求链完整
    final caPem = _caPem?.trim() ?? '';
    final chain = caPem.isEmpty ? cer : '$cer\n$caPem\n';

    var securityContext = SecurityContext(withTrustedRoots: true)
      ..useCertificateChainBytes(chain.codeUnits)
      ..allowLegacyUnsafeRenegotiation = true
      ..usePrivateKeyBytes(CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(rsaPrivateKey).codeUnits);

    _certificateMap[host] = securityContext;
    return securityContext;
  }

  /// 生成域名证书 PEM（仅证书，不含私钥）
  static Future<String> generateLeafCertificatePem(String host) async {
    if (_state != StartState.initialized) {
      await initCAConfig();
    }
    return generate(_caCert!, _serverKeyPair.publicKey as RSAPublicKey, _caPriKey, host);
  }

  /// 生成证书
  ///
  /// [remoteCert] 远程服务器真实证书, 若提供则复制其 Subject、SAN、有效期, 以通过客户端严格校验
  static String generate(X509CertificateData caRoot, RSAPublicKey serverPubKey, RSAPrivateKey caPriKey, String host,
      {X509CertificateData? remoteCert}) {
    //默认 subject 模板, 以及仅包含域名本身的 SAN
    Map<String, String> x509Subject = {
      'C': 'CN',
      'ST': 'BJ',
      'L': 'Beijing',
      'O': 'Proxy',
      'OU': 'QANIS',
      'CN': host,
    };
    List<String> sans = [host];
    DateTime? notBefore;
    DateTime? notAfter;

    //存在远程真实证书时, 复制其 Subject、SAN、有效期, 以通过客户端严格校验
    if (remoteCert != null) {
      x509Subject = _remoteSubject(remoteCert) ?? x509Subject;
      sans = _remoteSans(remoteCert) ?? sans;
      notBefore = remoteCert.validity.notBefore;
      notAfter = remoteCert.validity.notAfter;
    }

    return X509Utils.generateSelfSignedCertificate(caRoot, serverPubKey, caPriKey, 36,
        sans: sans,
        serialNumber: Random().nextInt(1000000).toString(),
        subject: x509Subject,
        issuerRawBytes: _caSubjectDnBytes,
        notBefore: notBefore,
        notAfter: notAfter);
  }

  /// 提取远程证书的 subject (key 为 OID 字符串, 如 2.5.4.3=CN), 整体替换默认模板避免 CN 重复; 为空返回 null
  static Map<String, String>? _remoteSubject(X509CertificateData remoteCert) {
    Map<String, String> subject = {};
    remoteCert.subject.forEach((key, value) {
      if (value != null && value.isNotEmpty) {
        subject[key] = value;
      }
    });
    return subject.isEmpty ? null : subject;
  }

  /// 提取远程证书的 DNS 类型 SAN, 过滤 DirName 等非 DNS 条目; 为空返回 null
  static List<String>? _remoteSans(X509CertificateData remoteCert) {
    var sans = remoteCert.subjectAlternativNames?.where((e) => !e.startsWith('DirName:')).toList();
    return (sans == null || sans.isEmpty) ? null : sans;
  }

  /// 获取证书主题hash
  static Future<String> systemCertificateName() async {
    if (_state != StartState.initialized) {
      await initCAConfig();
    }

    var subject = caCert!.subject;
    return '${X509Utils.getSubjectHashName(subject)}.0';
  }

  //重新生成根证书
  static Future<void> generateNewRootCA() async {
    if (_state != StartState.initialized) {
      await initCAConfig();
    }

    var generateRSAKeyPair = CryptoUtils.generateRSAKeyPair();
    var serverPubKey = generateRSAKeyPair.publicKey as RSAPublicKey;
    var serverPriKey = generateRSAKeyPair.privateKey as RSAPrivateKey;

    //根据CA证书subject来动态生成目标服务器证书的issuer和subject
    Map<String, String> x509Subject = {
      'C': 'CN',
      'ST': 'BJ',
      'L': 'Beijing',
      'O': 'Proxy',
      'OU': 'QANIS',
    };
    x509Subject['CN'] = 'QANIS CA (${DateTime.now().dateFormat()},${RandomUtil.randomString(6).toUpperCase()})';

    var csrPem = X509Utils.generateSelfSignedCertificate(
      _caCert!,
      serverPubKey,
      serverPriKey,
      825,
      sans: [x509Subject['CN']!],
      serialNumber: DateTime.now().millisecondsSinceEpoch.toString(),
      issuer: x509Subject,
      subject: x509Subject,
      keyUsage: ExtensionKeyUsage(ExtensionKeyUsage.keyCertSign),
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
      basicConstraints: BasicConstraints(isCA: true),
    );

    //重新写入根证书 (私有目录 /data/data/<pkg>/files)
    var caFile = await _caFilePath();
    await caFile.writeAsString(csrPem);

    //私钥
    var serverPriKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(serverPriKey);
    var keyFile = await _keyFilePath();
    await keyFile.writeAsString(serverPriKeyPem);
    _caPem = csrPem;
    _caCert = null;
    cleanCache();
    _state = StartState.uninitialized;
  }

  ///重置默认根证书
  static Future<void> resetDefaultRootCA() async {
    // 删除并重新生成一台设备专属的根证书 (等价于 "生成新证书")
    final caFile = await _caFilePath();
    if (await caFile.exists()) await caFile.delete();
    final keyFile = await _keyFilePath();
    if (await keyFile.exists()) await keyFile.delete();
    _caPem = null;
    _caCert = null;
    cleanCache();
    _state = StartState.uninitialized;
    await _createRootCaFiles();
    await initCAConfig();
  }

  static Future<void> initCAConfig() async {
    if (_state == StartState.initialized || _state == StartState.initializing) {
      return _initializationCompleter.future;
    }

    var startTime = DateTime.now().millisecondsSinceEpoch;

    _state = StartState.initializing;
    _initializationCompleter = Completer<void>();

    try {
      _serverKeyPair = CryptoUtils.generateRSAKeyPair();

      //从项目目录加入ca根证书
      var caPemFile = await certificateFile();
      var caPem = await caPemFile.readAsString();
      _caPem = caPem;
      _caCert = X509Utils.x509CertificateFromPem(caPem);
      //提取 CA subject DN 原始字节, 供签发叶子证书时作为 issuer, 保证与 CA 二进制精确匹配(兼容 iOS 严格校验)
      _caSubjectDnBytes = X509Utils.subjectDnBytesFromPem(caPem);
      //根据CA证书subject来动态生成目标服务器证书的issuer和subject

      //从项目目录加入ca私钥
      var keyFile = await privateKeyFile();
      _caPriKey = CryptoUtils.rsaPrivateKeyFromPem(await keyFile.readAsString());

      _state = StartState.initialized;
      _initializationCompleter.complete();
    } catch (e) {
      logger.e('init ca config error:$e');
      _state = StartState.uninitialized;
      _initializationCompleter.completeError(e);
    }

    logger.d('init ca config end cost:${DateTime.now().millisecondsSinceEpoch - startTime}');

    return _initializationCompleter.future;
  }

  /// CA 文件路径: 保存在应用私有目录 /data/data/<pkg>/files 下, 不随应用更新丢失
  static Future<File> _caFilePath() async {
    final appPath = await getApplicationSupportDirectory().then((value) => value.path);
    return File("$appPath${Platform.pathSeparator}ca.crt");
  }

  static Future<File> _keyFilePath() async {
    final appPath = await getApplicationSupportDirectory().then((value) => value.path);
    return File("$appPath${Platform.pathSeparator}ca_key.pem");
  }

  /// 生成一台设备专属的根证书 (RSA-2048, 10 年) 并写入私有目录。
  ///
  /// 不再使用随包分发的共享证书: 每个安装都有自己的密钥对, 只有本机安装的
  /// ca.crt 才能解开本机拦截的 HTTPS 流量。
  static Future<void> _createRootCaFiles() async {
    final keyPair = CryptoUtils.generateRSAKeyPair();
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final now = DateTime.now();
    final subject = <String, String>{
      'C': 'LY',
      'ST': 'Tripoli',
      'L': 'Tripoli',
      'O': 'QANIS',
      'OU': 'QANIS',
      'CN': 'QANIS CA (${now.dateFormat()},${RandomUtil.randomString(6).toUpperCase()})',
    };

    // 模板只需要签名算法, issuer/subject 由下面的参数显式提供
    final template = X509CertificateData(
      version: 3,
      serialNumber: BigInt.one,
      signatureAlgorithm: '1.2.840.113549.1.1.11',
      signatureAlgorithmReadableName: 'SHA256withRSA',
      issuer: subject,
      subject: subject,
      validity: X509CertificateValidity(notBefore: now, notAfter: now.add(const Duration(days: 3650))),
      publicKeyData: X509CertificatePublicKeyData(),
      subjectAlternativNames: [subject['CN']!],
      signature: '',
    );

    final pem = X509Utils.generateSelfSignedCertificate(template, publicKey, privateKey, 3650,
        sans: [subject['CN']!],
        serialNumber: DateTime.now().millisecondsSinceEpoch.toString(),
        issuer: subject,
        subject: subject,
        keyUsage: ExtensionKeyUsage(ExtensionKeyUsage.keyCertSign),
        extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
        basicConstraints: BasicConstraints(isCA: true));

    final caFile = await _caFilePath();
    await caFile.writeAsString(pem);
    final keyFile = await _keyFilePath();
    await keyFile.writeAsString(CryptoUtils.encodeRSAPrivateKeyToPem(privateKey));
    logger.d('generated device CA: ${subject['CN']} -> ${caFile.path}');
  }

  /// 证书文件
  static Future<File> certificateFile() async {
    var caFile = await _caFilePath();
    if (!(await caFile.exists())) {
      // 首次运行: 生成设备专属根证书 (不再使用随包共享的证书)
      await _createRootCaFiles();
    }

    return caFile;
  }

  ///证书pem格式内容
  static Future<String> certificatePem() async {
    var caFile = await certificateFile();
    return caFile.readAsString();
  }

  /// 私钥文件
  static Future<File> privateKeyFile() async {
    var keyFile = await _keyFilePath();
    if (!(await keyFile.exists())) {
      await _createRootCaFiles();
    }

    return keyFile;
  }

  ///生成 p12文件
  static Future<Uint8List> generatePkcs12(String? password) async {
    var caFile = await CertificateManager.certificateFile();
    var keyFile = await CertificateManager.privateKeyFile();
    return Pkcs12.generatePkcs12(await keyFile.readAsString(), [await caFile.readAsString()], password: password);
  }

  ///import p12文件
  static Future<void> importPkcs12(Uint8List pkcs12, String? password) async {
    var decodePkcs12 = Pkcs12.parsePkcs12(pkcs12, password: password);

    var caFile = await CertificateManager.certificateFile();
    var keyFile = await CertificateManager.privateKeyFile();
    if (decodePkcs12.length != 2) {
      throw Exception('Invalid pkcs12 file');
    }

    await keyFile.writeAsString(decodePkcs12[0]);
    await caFile.writeAsString(decodePkcs12[1]);

    cleanCache();
    _state = StartState.uninitialized;
    initCAConfig();
  }

  /// 获取证书详细信息
  static Future<X509CertificateData> getCertificateDetails() async {
    if (_state != StartState.initialized) {
      await initCAConfig();
    }
    return caCert!;
  }
}
