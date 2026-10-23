# Release planning and Xcode Cloud status

These commands are advisory/status tools. Neither performs a build, signs, initializes CloudKit, creates a tag, modifies release evidence, or claims TestFlight delivery.

## Read-only release plan

```sh
python3 -B tools/release.py plan
python3 -B tools/release.py plan v1.2.3
```

The plan is based exclusively on committed `HEAD`. Dirty staged, unstaged, and untracked edits are explicitly excluded, so it never combines a work-in-progress version with a committed schema fingerprint. Its output reports project/generated version consistency, the previous reachable release tag, changed model/registry source paths, and required human schema evidence. A first release has no prior comparison and reports schema evidence as required. “Advisory” is not preflight success: follow the release preflight and schema instructions in `docs/agents/workflow.md` and `docs/native/data-model.md`.

## Read-only App Store Connect status

Provide an exact 40- or 64-character commit SHA and either an App Store Connect Xcode Cloud build-run ID or workflow ID:

```sh
python3 -B tools/cloud_status.py <exact-commit-sha> --workflow-id <workflow-id> --version 1.2.3 --tag v1.2.3
python3 -B tools/cloud_status.py <exact-commit-sha> --build-run-id <build-run-id>
```

Authentication supports either a pre-issued bearer token in `ASC_TOKEN`, or an API key configured with `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_FILE` (path to the private `.p8` file). Do not put credentials in command arguments, repository files, or logs. Use an App Store Connect key with the least privileges suitable for reading Xcode Cloud data. The client itself sends GET requests only, fixes the API host to `api.appstoreconnect.apple.com`, refuses redirects and untrusted pagination links, and bounds pagination. It does not log authorization material; auth/network errors are sanitized. Credential setup and any live permission/auth validation are human tasks.

The report uses Apple's documented [`CiBuildRun` schema](https://developer.apple.com/documentation/appstoreconnectapi/cibuildrun): `isPullRequestBuild` selects the exact-commit field. For branch/tag builds, the requested SHA is matched to `attributes.destinationCommit.commitSha`; for pull-request builds it is matched to `attributes.sourceCommit.commitSha`. Both are commit metadata objects, not scalar strings. Missing/malformed documented commit metadata is an explicit error, not a guessed fallback. The status reports which field matched.

The report returns Apple's build-run progress/completion values. For each CI build it keeps `Build.attributes.version` as `buildNumber`, then reads the documented related `preReleaseVersion` resource for the marketing `version` and `platform`. The optional `--version` is compared only with that marketing version; missing relationship data is `unknown`, and a known nonmatch is `mismatch`. Multiple builds retain their individual numbers, marketing versions, and platforms. Build-run/build metadata is not evidence of TestFlight delivery. Verify TestFlight separately. See Apple's [`CiBuildRun` endpoint](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-cibuildruns-_id_), [`builds` endpoint](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-cibuildruns-_id_-builds), [`Build preReleaseVersion relationship endpoint`](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-builds-_id_-prereleaseversion), and [`PrereleaseVersion` schema](https://developer.apple.com/documentation/appstoreconnectapi/prereleaseversion).
