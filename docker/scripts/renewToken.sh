#!/bin/sh

export NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
#export NAMESPACE=bao
kubectl=kubectl

if [ "$BAO_CREDENTIAL" == "" ];then
  BAO_CREDENTIAL=bao-default-deploy-bao-credential
fi
bao_credential=$BAO_CREDENTIAL


#get root token
baoToken=`$kubectl get secret $bao_credential -n $NAMESPACE -o=jsonpath={.data.token} | base64 -d`
#get bao endpoint
endpoint=`$kubectl get secret $bao_credential -n $NAMESPACE -o=jsonpath={.data.endpoint} | base64 -d`

#get all BaoAccess CRs, if autoRenewToken == true, then renew
names=`$kubectl get BaoAccess -n $NAMESPACE -o=jsonpath='{range .items[*]}{.metadata.name}{","}'`
IFS=','
read -ra namesArr <<< "$names"

echo "The number of BaoAccess instances is: ${#namesArr[@]}"

for baoAccess in ${namesArr[@]}
do    
  echo "------------------ BaoAccess name is: $baoAccess ------------------"
  
  #check the status of baoAccess, ignore the failed instances
  status=`$kubectl get BaoAccess $baoAccess -n $NAMESPACE -o=jsonpath={.status.conditions[0].status}`
  
  if [ $status == "True" ]
  then
    echo "$baoAccess status is: $status, proceeding"
	autoRenewToken=`$kubectl get BaoAccess $baoAccess -n $NAMESPACE -o=jsonpath={.spec.autoRenewToken}`
	
	if [ $autoRenewToken ]
	then
	  echo "$baoAccess autoRenewToken is set, proceeding"
	  if [ $autoRenewToken == "true" ]
	  then
	    echo "$baoAccess autoRenewToken is: $autoRenewToken, start to renew bao token"

	    secretName=`$kubectl get BaoAccess $baoAccess -n $NAMESPACE -o=jsonpath={.spec.secretName}`
	    echo "secret name for $baoAccess is: $secretName"

	    accessToken=`$kubectl get secret $secretName -n $NAMESPACE -o=jsonpath={.data.token} | base64 -d`

	    status_code=$(curl -k -H "X-Vault-Token: $baoToken" -X POST --data "{\"token\": \"$accessToken\"}" --write-out %{http_code} --silent --output /dev/null $endpoint/v1/auth/token/renew)

        if [ $status_code -eq 200 ]
		then
          echo "Successfully renewed token for BaoAccess: $baoAccess"
        else
          echo "Error occurred when renew token for BaoAccess: $baoAccess"
        fi
	  else
	    echo "$baoAccess autoRenewToken is: $autoRenewToken, skip."
	  fi
	else
	  echo "$baoAccess autoRenewToken is NOT set which means it's false, skip."
	fi
  else
    echo "$baoAccess status is: $status, skip."
  fi
  #get the value of autoRenewToken
done