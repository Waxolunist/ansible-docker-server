#!/bin/bash

CRYPTO_IP=$(docker inspect cryptocurrency | grep IPAddress | tail -n 1 | awk '{print $2}' | sed 's/\"//g' | sed 's/,//g')
CRYPTO_PORT=$(docker inspect cryptocurrency | grep tcp | tail -n 1 | awk '{print $1}' | sed 's/\"//g' | sed 's/\/tcp:'//g)

curl -X POST http://${CRYPTO_IP}:${CRYPTO_PORT}/update/