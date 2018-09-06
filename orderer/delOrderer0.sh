#!/usr/bin/env bash

kubectl -n ordererorg1 delete svc orderer0
kubectl -n ordererorg1 delete deploy orderer0

