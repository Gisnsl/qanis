package com.qanis.app.vpn.transport.protocol

interface TransportHeader {
    fun getSourcePort(): Int
    fun getDestinationPort(): Int
}