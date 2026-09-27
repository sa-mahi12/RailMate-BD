# Source-side tooling

Only coordinator runs cloud builds, DB migrations, commit or push. This folder houses small scripts rather than another orchestration framework. No package in this source starter has been executed on the user's machine. `scripts/check_governance.sh` requires an origin remote; it will fail before repo creation as intended. `scripts/create_flutter_skeleton.sh` is an action, not a read-only check.
