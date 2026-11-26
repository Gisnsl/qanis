package com.qanis.app.vpn


fun formatTag(tag: String): String {
    return tag
}

val Any.TAG: String
    get() {
        return javaClass.name
    }
