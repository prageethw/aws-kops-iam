source ../../k8s-kops-cluster.temp
echo "wait till chaos monkey deployed as defined in Chaosfile.json "
cat Chaosfile.json  | sed -e  "s@NODE_ASG@$ASG_NAME@g" | tee chaos_file.temp.json
chaos-lambda deploy -c chaos_file.temp.json
