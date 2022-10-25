package com.vmware.se.vclustermanager

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class VclusterManagerApplication

fun main(args: Array<String>) {
	runApplication<VclusterManagerApplication>(*args)
}
