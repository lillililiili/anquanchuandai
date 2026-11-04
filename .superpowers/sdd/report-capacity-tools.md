# Capacity tools and isolated laboratory configuration

Implemented benchmark.mjs with pre-traffic laboratory identity/proof verification, synthetic device-only reports, ACK-based success, bounded pending requests, reconnect after timeout, and explicit business-GET success contracts. Added container resource and read-only DM8/MySQL transaction-wait samplers. No capacity result is claimed from these tools alone.

The laboratory uses .lab.env, private/lab/*, an independent wearable-lab-* project/network and loopback entry. Operations verify actual Docker network/container IDs and attachment aliases, DB schema, Redis database, shared root/store ID and backend/entry hashes; normal configuration overlap is rejected even through alternate aliases. prepare-lab-inventory.py registers only existing verified resources and refuses overwrite. Linux requires Python >=3.9, Compose >=2.24.4. Production configuration is unchanged by --lab.

Evidence (ignored output/dm8-cluster):
- gateway-final-with-benchmark.log: 17 tests,16 passed,1 POSIX-permission case skipped on Windows. Previous Linux gateway16 matrix covered that POSIX case.
- compose-lab-isolation-tests.log:10 passed; actual Compose rendering plus controlled Docker metadata negative cases.
- lab-inventory-smoke.log:actual dedicated DM8/Redis Docker identities and configuration accepted; duplicate registration refused without changing inventory. Existing lab dependencies gained a second isolated network attachment; daily application services were untouched.
- resource-sampler-smoke.log/jsonl,dm8-metrics-smoke.jsonl,mysql-metrics-smoke.jsonl:10-second sampler checks on real isolated resources. These are tool smoke tests, not load or capacity acceptance.
- Linux bash syntax check passed for all deployment shell scripts.
- review-benchmark-approved.md:independent static re-review closes the previous isolation P1; reviewer did not rerun tests.

Full Spring two-node traffic, persistent business reconciliation under load, equal-resource single/dual comparison, sustained load and Kylin/NFS/physical devices remain pending.
