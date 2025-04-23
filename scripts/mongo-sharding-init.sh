#!/bin/bash

wait_for_ping() {
  local container=$1
  local port=$2
  echo "Waiting for $container to be available..."
  until docker exec -i "$container" mongosh --port "$port" --quiet --eval "JSON.stringify(db.adminCommand('ping'))" | grep '"ok":1' >/dev/null; do
    sleep 2
  done
  echo "$container is ready."
}

wait_for_ping config1 27017
wait_for_ping config2 27017
wait_for_ping config3 27017

docker exec -i config1 mongosh --port 27017 <<EOF
try {
  rs.initiate({
    _id: "configReplSet",
    configsvr: true,
    members: [
      { _id: 0, host: "config1:27017", priority: 2 },
      { _id: 1, host: "config2:27017", priority: 1 },
      { _id: 2, host: "config3:27017", priority: 1 }
    ]
  });
} catch (e) {
  if (e.codeName !== 'AlreadyInitialized') throw e;
  print("configReplSet already initialized");
}
EOF

wait_for_ping shard1 27018
wait_for_ping shard2 27019
wait_for_ping router1 27020

docker exec -i shard1 mongosh --port 27018 <<EOF
try {
  rs.initiate({
    _id: "shard1ReplSet",
    members: [
      { _id: 0, host: "shard1:27018" }
    ]
  });
} catch (e) {
  if (e.codeName !== 'AlreadyInitialized') throw e;
  print("shard1ReplSet already initialized");
}
EOF
wait_for_ping shard1 27018

docker exec -i shard2 mongosh --port 27019 <<EOF
try {
  rs.initiate({
    _id: "shard2ReplSet",
    members: [
      { _id: 0, host: "shard2:27019" }
    ]
  });
} catch (e) {
  if (e.codeName !== 'AlreadyInitialized') throw e;
  print("shard2ReplSet already initialized");
}
EOF
wait_for_ping shard2 27019

docker exec -i router1 mongosh --port 27020 <<EOF
print("Adding shards...");
const res1 = sh.addShard("shard1ReplSet/shard1:27018");
print("Add shard1 result:", JSON.stringify(res1));
const res2 = sh.addShard("shard2ReplSet/shard2:27019");
print("Add shard2 result:", JSON.stringify(res2));

print("Enabling sharding for 'somedb' and sharding 'helloDoc' collection...");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });

print("Inserting data only after shards are added and sharding is configured...");

use somedb;
if (db.helloDoc.countDocuments() === 0) {
  let docs = [];
  for (let i = 0; i < 1000; i++) {
    docs.push({ name: "ly" + i, age: i });
  }
  db.helloDoc.insertMany(docs);
  print("Inserted 1000 sample documents into somedb.helloDoc");
} else {
  print("Skipping data insert — documents already present");
}
EOF

echo "Mongo sharded cluster initialized successfully."
