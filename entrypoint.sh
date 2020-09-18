#!/usr/bin/env bash

until $(nc -z $GANACHEHOST $GANACHEPORT);
do
  echo "waiting for ganache to come online"
  sleep 1
done

echo "Ganache is online. Deploying contracts starting in 5 secs"
sleep 5

truffle migrate --network remoteganache