# HLF-Orderer

A helm chart to deploy a single ordering service node into Kubernetes cluster.

## Confiugre and Deploy

Assume that multiple orgnizations has a agreement and construct a consortium.

### With tool Cryptogen
As without CA involved, all the keys and certificates are generated based on `crypto-config.yaml`, and genesis block for bootstrapping orderer is generated according to `configtx.yaml`.

Use cases:

1. Generates crypto artifacts using tool `cryptogen`

```
cryptogen generate --config /shared/artifacts/crypto-config.yaml
```

2. Generates genesis block

Make sure kafka brokers are set correctly in `configtx.yaml`

```
configtxgen -profile TwoOrgsOrdererGenesis -outputBlock genesis.block
```

Assume that users are using helm chart to deploy Fabric orderer into Kubernetes cluster(this is our goal)

3. Copy those config files to a persistent volume in Kubernetes

4. Modify the persistent volume claim and mount the config artifact to correct path

5. Make sure the following enviroments/configurations are correct set.

  - `ORDERER_FILELEDGER_LOCATION`(using a mount point to save data)
  - `ORDERER_GENERAL_LOCALMSPDIR` 
  - `ORDERER_GENERAL_LOCALMSPID`
  - `ORDERER_GENERAL_GENESISFILE`
  - `ORDERER_GENERAL_TLS_PRIVATEKEY`
  - `ORDERER_GENERAL_TLS_CERTIFICATE`

6. (Optional) customize service port

7. Helm install

```
helm install orderer/ -f <your_values.yaml>
```

### With CA

CA is used to genereate keys and cretificatoins, instead of using tool `cryptogen`.

1. Prepare infomation for CA client
  - CA Credential(username and password)
  - CA URL
  - CA TLS Certicatoin

2. Generate genesis block for orderer

3. Create screct objects to store CA related information and genesis block(Manually), or feed the base64 string of the `genesis.block` content to the values of helm chart

4. Make sure the following enviroments/configurations are correct set.

  - `ORDERER_FILELEDGER_LOCATION`(using a mount point to save data)
  - `ORDERER_GENERAL_LOCALMSPDIR`
  - `ORDERER_GENERAL_LOCALMSPID`
  - `ORDERER_GENERAL_GENESISFILE`
  - `ORDERER_GENERAL_TLS_PRIVATEKEY`
  - `ORDERER_GENERAL_TLS_CERTIFICATE`

5. (Optional) customize service port

6. Helm install

```
helm install orderer/ -f <your_values.yaml>
```

## Verify After Deploying

### Thought 1: Creating a test channel

From the role OSN played in a Fabric network, it is a little bit hard to verfiy that an OSN is servicing without additional information.

To achieve this, we can feed a `fake peer node` with requied information:

- CORE_PEER_LOCALMSPID
- CORE_PEER_MSPCONFIGPATH
- Public key of the orderer node(if TLS enabled)

While those information is not obvious avaible when deploying an OSN. As we don't know:

- How many orgs in the consortium
- How many peers in each org
- The names of peers and orgs

Note: One possible way to get those information is inspecting the genesis.block by `configtxgen` tool.

> While this method can be used when building helm chart for Fabric orderer. Usually we can define a simplest Fabric network, feeds the orderer
with genesis configuratoins, along with informatoin of peers for testing purpose.

### Thought 2: Looking for sign of success from logs

Up to now, this method can be considered as the most feasible/directly way to check the availability of orderer node.

```

t@fabrick8s:/home/ming/github-workspace/fabric-helm# grep "startThread.*\[channel: testchainid\]" /tmp/orderer0-1.log
2018-09-05 16:17:00.410 UTC [orderer/consensus/kafka] startThread -> INFO 192 [channel: testchainid] Producer set up successfully
2018-09-05 16:17:00.433 UTC [orderer/consensus/kafka] startThread -> INFO 1a3 [channel: testchainid] CONNECT message posted successfully
2018-09-05 16:17:00.441 UTC [orderer/consensus/kafka] startThread -> INFO 1c8 [channel: testchainid] Parent consumer set up successfully
2018-09-05 16:17:00.443 UTC [orderer/consensus/kafka] startThread -> INFO 1cf [channel: testchainid] Channel consumer set up successfully
2018-09-05 16:17:00.443 UTC [orderer/consensus/kafka] startThread -> INFO 1d0 [channel: testchainid] Start phase completed successfully
```

1. Verify the number of log records

```
number = $(kubeclt logs -n <namespace_if_need> <orderer_pod_name> --since=99h |grep "startThread.*\[channel: testchainid\]" |wc -l)

if [ "5" == "$number" ]; then
  exit 0
else
  exit 1
fi
```

2. Verify the last successfu starting message

```
kubeclt logs -n <namespace_if_need> <orderer_pod_name> |grep "Start phase completed successfully"
if [ $? -eq 0 ]; then
  exit 0
else
  exit 1
fi
```


### Thought 3: Query config block from system channel

Initialy, there is a system channel `testchainid` exists. We can query the config block for this channel to prove that orderer node is working.
Assume that we have a CLI/fabric-tools pod started:

1. Set environments
```
export CORE_PEER_TLS_ROOTCERT_FILE=/shared/crypto-config/ordererOrganizations/ordererorg1/orderers/orderer0.ordererorg1/msp/tlscacerts/tlsca.ordererorg1-cert.pem

export CORE_PEER_LOCALMSPID="Ordererorg1MSP"

export CORE_PEER_MSPCONFIGPATH=/shared/crypto-config/ordererOrganizations/ordererorg1/orderers/orderer0.ordererorg1/msp

export ORDERER_CA=/shared/crypto-config/ordererOrganizations/ordererorg1/orderers/orderer0.ordererorg1/msp/tlscacerts/tlsca.ordererorg1-cert.pem
```

2. Qeury config block

```
peer channel fetch config config_block.pb -o orderer0.ordererorg1:7050 -c "testchainid" --cafile $ORDERER_CA

2018-09-05 18:03:54.299 UTC [msp] GetLocalMSP -> DEBU 001 Returning existing local MSP
2018-09-05 18:03:54.300 UTC [msp] GetDefaultSigningIdentity -> DEBU 002 Obtaining default signing identity
2018-09-05 18:03:54.302 UTC [channelCmd] InitCmdFactory -> INFO 003 Endorser and orderer connections initialized
2018-09-05 18:03:54.303 UTC [msp] GetLocalMSP -> DEBU 004 Returning existing local MSP
2018-09-05 18:03:54.303 UTC [msp] GetDefaultSigningIdentity -> DEBU 005 Obtaining default signing identity
2018-09-05 18:03:54.304 UTC [msp] GetLocalMSP -> DEBU 006 Returning existing local MSP
2018-09-05 18:03:54.304 UTC [msp] GetDefaultSigningIdentity -> DEBU 007 Obtaining default signing identity
2018-09-05 18:03:54.304 UTC [msp/identity] Sign -> DEBU 008 Sign: plaintext: 0AD2060A1708021A06088AB5C0DC0522...ACD1D9774ABD12080A020A0012020A00
2018-09-05 18:03:54.304 UTC [msp/identity] Sign -> DEBU 009 Sign: digest: 0377488C78DF34E266A6722A8185182CCF4F9DDD9C894F165C5CA8FAC136249B
2018-09-05 18:03:54.306 UTC [channelCmd] readBlock -> DEBU 00a Received block: 0
2018-09-05 18:03:54.307 UTC [msp] GetLocalMSP -> DEBU 00b Returning existing local MSP
2018-09-05 18:03:54.307 UTC [msp] GetDefaultSigningIdentity -> DEBU 00c Obtaining default signing identity
2018-09-05 18:03:54.307 UTC [msp] GetLocalMSP -> DEBU 00d Returning existing local MSP
2018-09-05 18:03:54.307 UTC [msp] GetDefaultSigningIdentity -> DEBU 00e Obtaining default signing identity
2018-09-05 18:03:54.307 UTC [msp/identity] Sign -> DEBU 00f Sign: plaintext: 0AD2060A1708021A06088AB5C0DC0522...E139E2B1A3E112080A021A0012021A00
2018-09-05 18:03:54.307 UTC [msp/identity] Sign -> DEBU 010 Sign: digest: DCB93F9EE11AF6D93F86318B96058D30DEEE3C93580A28B68F31374876DF2A26
2018-09-05 18:03:54.309 UTC [channelCmd] readBlock -> DEBU 011 Received block: 0
2018-09-05 18:03:54.310 UTC [main] main -> INFO 012 Exiting.....
```

3. Check to execution result

```
if [ $? -eq 0 ]; then
  peer channel fetch config config_block.pb -o orderer0.ordererorg1:7050 -c "testchainid" --cafile $ORDERER_CA  2>&1 |grep "Error"
  if [ $? -eq 0 ]; then
    exit 1
  if
  exit 0
else
  exit 1
fi
```

