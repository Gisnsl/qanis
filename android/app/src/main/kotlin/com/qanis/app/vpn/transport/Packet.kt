package com.qanis.app.vpn.transport

import com.qanis.app.vpn.transport.protocol.IP4Header
import com.qanis.app.vpn.transport.protocol.TransportHeader

class Packet(var ipHeader: IP4Header, var transportHeader: TransportHeader, var buffer: ByteArray) {
}