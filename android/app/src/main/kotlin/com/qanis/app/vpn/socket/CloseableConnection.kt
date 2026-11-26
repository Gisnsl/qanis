package com.qanis.app.vpn.socket

import com.qanis.app.vpn.Connection

interface CloseableConnection {
    /**
     * 关闭连接
     */
    fun closeConnection(connection: Connection)
}