# Final release migration rebind

Status: **PASS: isolated MySQL → DM8 → MySQL backup/restore and three reconciliations on the exact release JAR**.

- Final application JAR: `output/dm8-cluster/fdc-admin-final-35290a86.jar`; SHA-256 `35290a865fe8169bdaeeacab57151e379b7235a2808a4e7cbf0e8358158e8614` verified before extraction. Runtime extracted from the complete JAR with the migration wrapper. No runtime overlay or Maven build.
- Recursive comparison against previously exercised SHA `71ab732edd82ded8c0472cf5d88555bbae6e5b77483c3fc100d5cf1d5c65a7bb`: 65,055 old and 65,056 new non-directory payload entries. Eight changed class entries and one added class entry (router, assignment service and nested class, guardian error/bootstrap, dependency error, and three system POJOs). No SQL, SchemaLifecycle, migration database adapters or JDBC dependency payload changed. See `output/dm8-cluster/migration-release/artifact-comparison.json`.
- The four prior tool/fixture sources match the old acceptance hashes and were compiled against final-JAR dependencies with compiler heap capped at 256 MiB. The output directory retains the private per-schema configs and safe compile/comparison/resource records.
- Fresh targets: DM8 `WEARABLE_MIGRATION_RL4D`, MySQL `wearable_migration_rl4b`. The source remains the isolated and previously seeded MySQL `wearable_migration_1104_fsrc`. After parent release, both targets were checked for account/schema absence before CREATE; the schema lifecycle from the release JAR initialized and validated each. The migration wrapper validated the exact 64-character database instance identities, designated localhost endpoints (MySQL 15306, DM8 15237), shared configuration continuity, and matching stopped fixture-app identities. All three fixture-app containers remained in created state and were never started; see container-readback.log.

The earlier real process kill (PID 38424), concurrent journal lock, lost-owner refusal, high-water mark restoration, and row/file/JSON tamper matrix remain bound to the old `71ab732e` JAR in [report-migration-final.md](report-migration-final.md). They have not been rerun on the release JAR.

## Real round trip and readback

The serial phases exited 0: export the original MySQL source → import into fresh DM8 → verify generated keys and recovery audit JSON → reconcile DM8 against the source bundle → export DM8 → import into a separate fresh MySQL target → repeat generated-key and recovery audit probes → reconcile against the DM8 bundle and against the original source bundle.

| Bundle | Tables | Rows | Files | Manifest SHA-256 |
|---|---:|---:|---:|---|
| source-export | 99 | 28 | 4 | `77306928f0e99d415de1847a9cdf43846b373d33783b99f473324aba62f94d4b` |
| dm-export | 99 | 28 | 4 | `00956b04b0eab42d09d17d9ad6b2139ebca9fed8084a3212ca8ed5d9c9005f59` |

Both manifests bind the exact release application SHA. Every reconciliation completed and verified the per-table canonical content hashes, identity watermarks and file hashes. Each verified **91 restored tables / 27 restored rows**. Eight volatile tables were archive-only; they include the remaining archived row.

| Reconciliation | Next device report ID | Next notice ID | Report SHA-256 |
|---|---:|---:|---|
| target-reconciliation.json | 8000000000002 | 1000002 | `bdb5b71ca911e7fe5788e5d9d9a17c1d775f9fec809bb578c8c8045932cae2a2` |
| back-reconciliation.json | 8000000000003 | 1000003 | `9f2a273408625ac3ebf386689a378d35602cf56b30ecdfa1e7c363f5e6d60fa0` |
| back-versus-original.json | 8000000000003 | 1000003 | `22f0abb42d1f26afa223b9bf8c5594172e3d614006a2bf9eae073b002a66f669` |

The fixture also checked real generated BIGINT and INT identities, explicit zero-ID preservation and recovery-audit JSON readback in both targets. The independently recomputed final JAR SHA matched the initial value; all four fixture source hashes matched both the prior acceptance and the live source readback.

Resource samples never breached the thresholds: minimum recorded available host RAM was 2793.83 MiB; peak recorded DM memory was 89.54% of its unchanged 3 GiB limit. This is lab evidence. The first pre-start check stopped before starting MySQL because Docker's running port map is absent for stopped containers. A separate read-only check confirmed the configured binding and exact ID before starting only the authorized MySQL lab container; running endpoint/ID and the successful transfer then confirmed connectivity. No phase that created or imported data was replayed.

Evidence: `output/dm8-cluster/migration-release/verification-summary.json`, `artifact-comparison.json`, `fixture-source-hashes.json`, `resources.jsonl`, `container-readback.log`, and serial phase logs. Bundles, configurations, journals and detailed reconciliation reports remain under the private directory; do not include it in a public delivery. No old target or fault schema, active LAB1104B app schema, shared valid-app data, or Redis DB 6 was modified by this run. No product source, git index, commit or merge changes were made.
