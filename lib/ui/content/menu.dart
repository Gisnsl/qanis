import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/storage/favorites.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/ui/component/svg_icon.dart';
import 'package:qanis/utils/curl.dart';
import 'package:qanis/utils/platform.dart';
import 'package:qanis/utils/quick_share.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/export_request.dart';
import '../../utils/python.dart';
import '../mobile/menu/bottom_navigation.dart';
import '../mobile/request/request_editor.dart';
import '../mobile/setting/request_map.dart';
import 'code_snippet.dart';
import 'request_detail_tabs.dart';

///分享按钮
class ShareWidget extends StatelessWidget {
  final ProxyServer? proxyServer;
  final HttpRequest? request;
  final HttpResponse? response;

  const ShareWidget({super.key, required this.proxyServer, this.request, this.response});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return PopupMenuButton(
      icon: const Icon(Icons.share, size: 24),
      offset: const Offset(0, 30),
      itemBuilder: (BuildContext context) {
        return [
          PopupMenuItem(
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Text(localizations.shareUrl),
            onTap: () async {
              if (request == null) {
                FlutterToastr.show(localizations.emptyData, context);
                return;
              }
              SharePlus.instance.share(ShareParams(
                  text: request!.requestUrl,
                  subject: localizations.proxyPinSoftware,
                  sharePositionOrigin: await _sharePositionOrigin(context)));
            },
          ),
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Text("${localizations.share} ${localizations.requestResponse}"),
              onTap: () async {
                if (request == null) {
                  FlutterToastr.show(localizations.emptyData, context);
                  return;
                }
                var file = XFile.fromData(utf8.encode(copyRequest(request!, response)),
                    name: localizations.captureDetail, mimeType: "txt");

                SharePlus.instance.share(ShareParams(
                    files: [file],
                    fileNameOverrides: ['request.txt'],
                    subject: localizations.proxyPinSoftware,
                    sharePositionOrigin: await _sharePositionOrigin(context)));
              }),
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Text(localizations.shareCurl),
              onTap: () async {
                if (request == null) {
                  return;
                }
                var text = curlRequest(request!);
                var file = XFile.fromData(utf8.encode(text), name: "cURL.txt", mimeType: "txt");

                SharePlus.instance.share(ShareParams(
                    files: [file],
                    fileNameOverrides: ["cURL.txt"],
                    subject: localizations.proxyPinSoftware,
                    sharePositionOrigin: await _sharePositionOrigin(context)));
              }),
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Text("${localizations.share} Fetch API"),
              onTap: () async {
                if (request == null) {
                  return;
                }
                var text = copyAsFetch(request!);
                SharePlus.instance
                    .share(ShareParams(text: text, sharePositionOrigin: await _sharePositionOrigin(context)));
              }),
          PopupMenuItem(
            enabled: QuickShareService.isRemoteConnected(proxyServer),
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Text('${localizations.share} ${localizations.connectRemote}'),
            onTap: () => _quickShareToRemote(context, localizations),
          ),
        ];
      },
    );
  }

  Future<void> _quickShareToRemote(BuildContext context, AppLocalizations localizations) async {
    if (request == null) {
      FlutterToastr.show(localizations.emptyData, context);
      return;
    }

    if (!QuickShareService.isRemoteConnected(proxyServer)) {
      FlutterToastr.show('${localizations.notConnected} ${localizations.remoteDevice}', context);
      return;
    }

    final success = await QuickShareService.sendRequestToRemote(proxyServer!, request!);
    if (!context.mounted) {
      return;
    }

    if (success) {
      FlutterToastr.show(localizations.requestSuccess, context);
    } else {
      FlutterToastr.show('${localizations.send}${localizations.fail}', context);
    }
  }

  Future<Rect?> _sharePositionOrigin(BuildContext context) async {
    RenderBox? box;
    if (await Platforms.isIpad() && context.mounted) {
      box = context.findRenderObject() as RenderBox?;
    }
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }
}

class DetailMenuWidget extends StatelessWidget {
  final HttpRequest? request;

  const DetailMenuWidget({
    super.key,
    this.request,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return PopupMenuButton(
        offset: const Offset(0, 30),
        padding: const EdgeInsets.all(0),
        itemBuilder: (context) => [
              PopupMenuItem(
                  height: 44,
                  child: const Row(children: [
                    SvgIcon("compose", size: 18, color: DarkPalette.text2),
                    SizedBox(width: 12),
                    Text("Compose")
                  ]),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              MobileRequestEditor(request: request, proxyServer: ProxyServer.current)));
                    });
                  }),
              PopupMenuItem(
                  height: 44,
                  child: Row(children: [
                    const SvgIcon("download", size: 18, color: DarkPalette.text2),
                    const SizedBox(width: 12),
                    Text(localizations.save)
                  ]),
                  onTap: () {
                    if (request == null) return;

                    showDialog(
                        context: context,
                        builder: (menuContext) {
                          return AlertDialog(
                              title: Text(localizations.save),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.request),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportRequest(request!);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.requestBody),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportRequestBody(request!);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.response),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportResponse(request?.response);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.responseBody),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportResponseBody(request?.response);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.requestResponse),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        if (request == null) {
                                          return;
                                        }
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportRequestAndResponse(request!, request?.response);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text("HAR"),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        if (request == null) {
                                          return;
                                        }
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportHar(request!);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ));
                        });
                  }),
              PopupMenuItem(
                  height: 44,
                  child: const Row(children: [
                    SvgIcon("snippet", size: 18, color: DarkPalette.text2),
                    SizedBox(width: 12),
                    Text("Code Snippet")
                  ]),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (request == null || !context.mounted) {
                        return;
                      }
                      Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => CodeSnippetPage(request: request!)));
                    });
                  }),
              PopupMenuItem(
                  height: 44,
                  child: const Row(children: [
                    SvgIcon("chat", size: 18, color: DarkPalette.text2),
                    SizedBox(width: 12),
                    Text("Comment")
                  ]),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (request == null || !context.mounted) return;
                      showDialog(
                          context: context,
                          builder: (dialogContext) {
                            final controller = TextEditingController(text: request!.comment);
                            return AlertDialog(
                              title: const Text('Comment', style: TextStyle(fontSize: 17)),
                              content: TextField(
                                controller: controller,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                    hintText: 'Add a note to this request', border: OutlineInputBorder()),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(dialogContext),
                                    child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () {
                                      request!.comment = controller.text;
                                      Navigator.pop(dialogContext);
                                      FlutterToastr.show('Comment saved', context);
                                    },
                                    child: const Text('Save')),
                              ],
                            );
                          });
                    });
                  }),
              PopupMenuItem(
                  height: 44,
                  child: const Row(children: [
                    SvgIcon("sliders", size: 18, color: DarkPalette.text2),
                    SizedBox(width: 12),
                    Text("Customize Tabs")
                  ]),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      showDialog(
                          context: context,
                          builder: (dialogContext) {
                            return AlertDialog(
                              title: const Text('Customize Tabs', style: TextStyle(fontSize: 17)),
                              content: StatefulBuilder(
                                  builder: (ctx, setDialogState) => SingleChildScrollView(
                                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                                          for (final tab in RequestDetailTabs.available)
                                            CheckboxListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              value: RequestDetailTabs.enabled.contains(tab),
                                              title: Text(tab, style: const TextStyle(fontSize: 13)),
                                              onChanged: (on) => setDialogState(() {
                                                if (on == true) {
                                                  RequestDetailTabs.enabled.add(tab);
                                                } else {
                                                  RequestDetailTabs.enabled.remove(tab);
                                                }
                                              }),
                                            ),
                                        ]),
                                      )),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(dialogContext),
                                    child: const Text('Done')),
                              ],
                            );
                          });
                    });
                  }),
              PopupMenuItem(
                  height: 44,
                  child: const Row(children: [
                    SvgIcon("favorite", size: 18, color: DarkPalette.text2),
                    SizedBox(width: 12),
                    Text("Favorite")
                  ]),
                  onTap: () {
                    if (request == null) return;

                    FavoriteStorage.addFavorite(request!);
                    FlutterToastr.show(localizations.addSuccess, context);
                  }),
              PopupMenuItem(
                  height: 44,
                  child: Row(children: [
                    const SvgIcon("swap", size: 18, color: DarkPalette.text2),
                    const SizedBox(width: 12),
                    Text(localizations.requestMap)
                  ]),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      navigator(
                          context, MobileRequestMapEdit(url: request?.domainPath, title: request?.hostAndPort?.host));
                    });
                  }),
            ],
        child: const SizedBox(height: 38, width: 38, child: Icon(Icons.more_vert, size: 28)));
  }
}
