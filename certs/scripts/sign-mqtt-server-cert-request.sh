#!/bin/sh
openssl ca -batch -key mypassword -config openssl-ca.cnf -policy signing_policy -extensions signing_req_server -out mqttservercert.pem -infiles mqttservercert.csr

