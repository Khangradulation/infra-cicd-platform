#!/usr/bin/env python3
"""Minimal fake `aws` CLI for testing scripts/deploy-ecs.sh offline.

Behaviour is selected by FAKE_AWS_SCENARIO:
  success        rollout completes; tasks run the new revision with the right digest
  rollback       circuit breaker rolls the PRIMARY deployment back to the old revision
  failed         PRIMARY deployment reports rolloutState FAILED
  wrong_digest   rollout completes but a task reports a different image digest
  missing_image  the digest is not in ECR
  stuck          rollout never completes (exercise the timeout)
State between calls is kept in FAKE_AWS_STATE (a JSON file).
"""

from __future__ import annotations

import json
import os
import sys

SCENARIO = os.environ.get("FAKE_AWS_SCENARIO", "success")
STATE = os.environ["FAKE_AWS_STATE"]
DIGEST = os.environ["FAKE_AWS_DIGEST"]
ACCOUNT = "111111111111"
REGION = "us-east-1"
OLD_TD = f"arn:aws:ecs:{REGION}:{ACCOUNT}:task-definition/icp-dev:4"
NEW_TD = f"arn:aws:ecs:{REGION}:{ACCOUNT}:task-definition/icp-dev:5"
TG = f"arn:aws:elasticloadbalancing:{REGION}:{ACCOUNT}:targetgroup/icp-dev-tg/abc"
LB = f"arn:aws:elasticloadbalancing:{REGION}:{ACCOUNT}:loadbalancer/app/icp-dev-alb/abc"


def load() -> dict:
    if os.path.exists(STATE):
        with open(STATE) as fh:
            return json.load(fh)
    return {"service_td": OLD_TD, "polls": 0, "calls": []}


def save(st: dict) -> None:
    with open(STATE, "w") as fh:
        json.dump(st, fh)


def arg(name: str) -> str | None:
    a = sys.argv
    return a[a.index(name) + 1] if name in a else None


def emit(obj) -> None:
    query = arg("--query")
    out = arg("--output")
    # Tiny subset of JMESPath used by the script.
    if query:
        obj = jmes(query, obj)
    if out == "text":
        if isinstance(obj, list):
            print("\t".join(str(x) for x in obj))
        else:
            print(obj)
    else:
        print(json.dumps(obj))


def jmes(q: str, obj):
    table = {
        "services[0].taskDefinition": lambda o: o["services"][0]["taskDefinition"],
        "taskDefinition.taskDefinitionArn": lambda o: o["taskDefinition"]["taskDefinitionArn"],
        "service.deployments[?status==`PRIMARY`].id": lambda o: ["ecs-svc/1"],
        "taskArns": lambda o: o["taskArns"],
        "length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])": lambda o: sum(
            1 for t in o["TargetHealthDescriptions"] if t["TargetHealth"]["State"] == "healthy"
        ),
        "LoadBalancers[0].LoadBalancerArn": lambda o: o["LoadBalancers"][0]["LoadBalancerArn"],
        "LoadBalancers[0].DNSName": lambda o: o["LoadBalancers"][0]["DNSName"],
        "Listeners[?Port==`443`].Port": lambda o: [x["Port"] for x in o["Listeners"] if x["Port"] == 443],
    }
    if q not in table:
        sys.exit(f"fake aws: unsupported query {q}")
    return table[q](obj)


def main() -> int:
    st = load()
    svc, op = sys.argv[1], sys.argv[2]
    st["calls"].append(f"{svc} {op}")

    if (svc, op) == ("ecr", "describe-images"):
        if SCENARIO == "missing_image":
            print("ImageNotFoundException", file=sys.stderr)
            save(st)
            return 254
        emit({"imageDetails": [{"registryId": ACCOUNT, "imageDigest": DIGEST, "imageTags": ["a" * 40]}]})

    elif (svc, op) == ("ecs", "describe-services"):
        primary_td = st["service_td"]
        state = "IN_PROGRESS"
        if st["polls"] >= 1:
            if SCENARIO in ("success", "wrong_digest"):
                state = "COMPLETED"
            elif SCENARIO == "rollback":
                primary_td, state = OLD_TD, "COMPLETED"
            elif SCENARIO == "failed":
                state = "FAILED"
        if st.get("updated"):
            st["polls"] += 1
        emit({
            "services": [{
                "taskDefinition": primary_td,
                "loadBalancers": [{"targetGroupArn": TG}],
                "deployments": [{
                    "status": "PRIMARY", "taskDefinition": primary_td, "rolloutState": state,
                    "rolloutStateReason": "circuit breaker" if SCENARIO in ("rollback", "failed") else "",
                    "runningCount": 1, "desiredCount": 1,
                }],
                "events": [{"createdAt": "now", "message": f"fake event ({SCENARIO})"}],
            }]
        })

    elif (svc, op) == ("ecs", "describe-task-definition"):
        emit({"taskDefinition": {
            "taskDefinitionArn": OLD_TD, "revision": 4, "status": "ACTIVE", "family": "icp-dev",
            "containerDefinitions": [{"name": "app", "image": "old@sha256:" + "0" * 64}],
            "requiresAttributes": [], "compatibilities": ["FARGATE"],
        }})

    elif (svc, op) == ("ecs", "register-task-definition"):
        path = arg("--cli-input-json").removeprefix("file://")
        with open(path) as fh:
            td = json.load(fh)
        st["registered_image"] = td["containerDefinitions"][0]["image"]
        st["registered_keys"] = sorted(td)
        emit({"taskDefinition": {"taskDefinitionArn": NEW_TD}})

    elif (svc, op) == ("ecs", "update-service"):
        st["service_td"] = arg("--task-definition")
        st["updated"] = True
        emit({"service": {"deployments": [{"status": "PRIMARY", "id": "ecs-svc/1"}]}})

    elif (svc, op) == ("ecs", "list-tasks"):
        emit({"taskArns": [f"arn:aws:ecs:{REGION}:{ACCOUNT}:task/icp-dev/t1"]})

    elif (svc, op) == ("ecs", "describe-tasks"):
        d = DIGEST if SCENARIO != "wrong_digest" else "sha256:" + "f" * 64
        emit({"tasks": [{
            "taskArn": f"arn:aws:ecs:{REGION}:{ACCOUNT}:task/icp-dev/t1", "lastStatus": "RUNNING",
            "taskDefinitionArn": NEW_TD, "containers": [{"name": "app", "imageDigest": d}],
        }]})

    elif (svc, op) == ("elbv2", "describe-target-health"):
        emit({"TargetHealthDescriptions": [{"TargetHealth": {"State": "healthy"}}]})

    elif (svc, op) == ("elbv2", "describe-load-balancers"):
        emit({"LoadBalancers": [{"LoadBalancerArn": LB, "DNSName": "icp-dev-alb-123.us-east-1.elb.amazonaws.com"}]})

    elif (svc, op) == ("elbv2", "describe-listeners"):
        emit({"Listeners": [{"Port": 80}]})

    else:
        sys.exit(f"fake aws: unsupported call {svc} {op}")

    save(st)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
