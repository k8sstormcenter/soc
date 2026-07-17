
mock_log = [
{
        "node_name": "gke-k8s-caas-0008-beta-user-pool-40badfb2-d52w",
        "process_exec": {
            "parent": {
                "arguments": "-c \"nsenter -t 1 -a /bin/bash && sleep infinity;\"",
                "auid": 4294967295,
                "binary": "/bin/sh",
                "cwd": "/",
                "docker": "88a138a1e320c55cfcc8dd5d8c52852",
                "exec_id": "Z2tlLWs4cy1jYWFzLTAwMDgtYmV0YS11c2VyLXBvb2wtNDBiYWRmYjItZDUydzo1MTI3OTYzMjg3NTkzOToxMjM4NTI=",
                "flags": "execve rootcwd clone",
                "in_init_tree": False,
                "parent_exec_id": "Z2tlLWs4cy1jYWFzLTAwMDgtYmV0YS11c2VyLXBvb2wtNDBiYWRmYjItZDUydzo1MTI2ODI1ODgwOTY2OToxMjM1OTg=",
                "pid": 123852,
                "pod": {
                    "container": {
                        "id": "containerd://88a138a1e320c55cfcc8dd5d8c528523c2f48faf8cf1b87d7723bab968e08664",
                        "image": {
                            "id": "docker.io/library/ubuntu@sha256:1e622c5f073b4f6bfad6632f2616c7f59ef256e96fe78bf6a595d1dc4376ac02",
                            "name": "docker.io/library/ubuntu:latest"
                        },
                        "name": "kh-calibration-ce-1-pod",
                        "start_time": "2025-04-23T10:22:32Z"
                    },
                    "name": "kh-calibration-ce-1",
                    "namespace": "default",
                    "pod_labels": {
                        "app": "kubehound-edge-test"
                    },
                    "workload": "kh-calibration-ce-1",
                    "workload_kind": "Pod"
                },
                "start_time": "2025-04-23T10:22:32.037987445Z",
                "tid": 123852,
                "uid": 0
            },
            "process": {
                "arguments": "-t 1 -a /bin/bash",
                "auid": 4294967295,
                "binary": "/usr/bin/nsenter",
                "cwd": "/",
                "docker": "88a138a1e320c55cfcc8dd5d8c52852",
                "exec_id": "Z2tlLWs4cy1jYWFzLTAwMDgtYmV0YS11c2VyLXBvb2wtNDBiYWRmYjItZDUydzo1MTI3OTY0NDk3NzM0NDoxMjM4NjU=",
                "flags": "execve rootcwd clone",
                "in_init_tree": False,
                "parent_exec_id": "Z2tlLWs4cy1jYWFzLTAwMDgtYmV0YS11c2VyLXBvb2wtNDBiYWRmYjItZDUydzo1MTI3OTYzMjg3NTkzOToxMjM4NTI=",
                "pid": 123865,
                "pod": {
                    "container": {
                        "id": "containerd://88a138a1e320c55cfcc8dd5d8c528523c2f48faf8cf1b87d7723bab968e08664",
                        "image": {
                            "id": "docker.io/library/ubuntu@sha256:1e622c5f073b4f6bfad6632f2616c7f59ef256e96fe78bf6a595d1dc4376ac02",
                            "name": "docker.io/library/ubuntu:latest"
                        },
                        "name": "kh-calibration-ce-1-pod",
                        "start_time": "2025-04-23T10:22:32Z"
                    },
                    "name": "kh-calibration-ce-1",
                    "namespace": "default",
                    "pod_labels": {
                        "app": "kubehound-edge-test"
                    },
                    "workload": "kh-calibration-ce-1",
                    "workload_kind": "Pod"
                },
                "start_time": "2025-04-23T10:22:32.050115698Z",
                "tid": 123865,
                "uid": 0
            }
        },
        "time": "2025-04-23T10:22:32.050087206Z"
    },
]