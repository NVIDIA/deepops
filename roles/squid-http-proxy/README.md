squid-http-proxy
================

A very basic Ansible role for configuring an http proxy server using
[Squid](http://www.squid-cache.org/).

This role is included primarily for testing purposes, to make it easier to test deployments behind an HTTP proxy.
This probably shouldn't be used as a production proxy server.


Variables
---------

* `squid_http_port`: Set the port Squid will listen on (default `'8888'`)
* `squid_disable_caching`: Prevents Squid from caching any content (default `true`)
