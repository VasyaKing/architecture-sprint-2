#!/bin/bash

# Step 1: Wait for config replica set to be ready
until docker exec -i config1 mongosh --port 27017 --quiet --eval "JSON.stringify(db.adminCommand('ping'))" | grep '"ok":1' >/dev/null; do
  echo "Waiting for config server to be available..."
  sleep 2
done

# Step 2: Initiate config replica set
docker exec -i config1 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "config1:27017", priority: 2 },
    { _id: 1, host: "config2:27017", priority: 1 },
    { _id: 2, host: "config3:27017", priority: 1 }
  ]
})
EOF

# Step 3: Wait for shard1_1 to be available
until docker exec -i shard1_1 mongosh --port 27018 --quiet --eval "JSON.stringify(db.adminCommand('ping'))" | grep '"ok":1' >/dev/null; do
  echo "Waiting for shard1_1 to be available..."
  sleep 2
done

# Step 4: Initiate shard1 replica set
docker exec -i shard1_1 mongosh --port 27018 <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1_1:27018" },
    { _id: 1, host: "shard1_2:27018" },
    { _id: 2, host: "shard1_3:27018" }
  ]
})
EOF

# Step 5: Wait for shard2_1 to be available
until docker exec -i shard2_1 mongosh --port 27019 --quiet --eval "JSON.stringify(db.adminCommand('ping'))" | grep '"ok":1' >/dev/null; do
  echo "Waiting for shard2_1 to be available..."
  sleep 2
done

# Step 6: Initiate shard2 replica set
docker exec -i shard2_1 mongosh --port 27019 <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2_1:27019" },
    { _id: 1, host: "shard2_2:27019" },
    { _id: 2, host: "shard2_3:27019" }
  ]
})
EOF

# Step 7: Wait for mongos to be available
until docker exec -i router1 mongosh --port 27020 --quiet --eval "JSON.stringify(db.adminCommand('ping'))" | grep '"ok":1' >/dev/null; do
  echo "Waiting for mongos router to be available..."
  sleep 2
done

# Step 8: Add shards and enable sharding
docker exec -i router1 mongosh --port 27020 <<EOF
sh.addShard("shard1ReplSet/shard1_1:27018,shard1_2:27018,shard1_3:27018")
sh.addShard("shard2ReplSet/shard2_1:27019,shard2_2:27019,shard2_3:27019")

sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })

use somedb
for (let i = 0; i < 1000; i++) db.helloDoc.insert({ name: "ly" + i, age: i })
EOF
