#!/bin/bash
echo "======== start clean docker containers logs ========"
logs=$(find /var/lib/docker/containers/ -name *-json.log)
for log in $logs
        do
                echo "clean logs : $log"
                cat /dev/null > $log
        done

docker system prune -f
docker volume rm $(docker volume ls -f "dangling=true" -q)
echo "======== end clean docker containers logs ========"
