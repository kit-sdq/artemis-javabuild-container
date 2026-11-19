# Artemis Java Build Container

Docker image `ghcr.io/kit-sdq/artemis-javabuild` for the Java programming exercises on Artemis at KIT.
It contains Maven, a Temurin JDK and a pre-filled Maven repository, so the exercise builds run **fully offline**:
no request to Maven Central, GitLab or any other repository, not even for SNAPSHOT updates.

> [!WARNING]
> **Rebuild this image after every deployment of the [test-framework](https://gitlab.kit.edu/kit/kastel/artemis/test-framework) (including SNAPSHOTs).**
> The image only contains the test-framework that was deployed when it was built.
> Without a rebuild, Artemis keeps using the old test-framework, and new plugin or dependency versions make **all exercise builds fail**.
>
> Run the [Docker Push workflow](https://github.com/kit-sdq/artemis-javabuild-container/actions/workflows/docker-publish.yml) ("Run workflow" on `main`) or:
>
> ```sh
> gh workflow run docker-publish.yml --repo kit-sdq/artemis-javabuild-container --ref main
> ```

## How it works
1. **Versions:** [`pom.xml`](pom.xml) only references `edu.kit.kastel.sdq.artemis:test-framework-parent`.
   All plugin and dependency versions (and the Java version) are pinned there. The exercise test repositories use the same parent,
   so the image caches exactly the versions the exercises need. The `pom.xml` to copy into an exercise is in the README of the test-framework.
2. **Warm-up:** the image build runs exactly the commands Artemis runs on the sample project (`assignment/src`, `test/`, `staticCodeAnalysisConfig/`):
   ```sh
   mvn -B clean compile
   mvn -B test
   mvn -B spotbugs:spotbugs checkstyle:checkstyle pmd:pmd pmd:cpd
   ```
   This fills `/repo` with all plugins and their runtime dependencies (e.g. surefire providers, SpotBugs, PMD).
3. **Offline:** afterwards the user settings `/maven-home/.m2/settings.xml` set `<offline>true</offline>`.
   `MAVEN_OPTS` fixes `user.home` to `/maven-home`, so the settings are used by every user, as Jenkins runs the container with `-u <uid>:<gid>` and without a home directory.
   (`<offline>` in the global `settings.xml` would be ignored by Maven.)
4. **Self-check:** the three commands run again offline. The image build fails if anything is missing in `/repo`.

An exercise that requests a version that is not cached fails with `Cannot access central (...) in offline mode` instead of downloading it.

## Environment
| Variable | Value |
|---|---|
| `MAVEN_OPTS` | `-Dmaven.repo.local=/repo -Duser.home=/maven-home -Daether.remoteRepositoryFilter.prefixes=false` |
| `RUN_IN_ARTEMIS` | `true` (used by the test-framework) |

## Updating
- **Test-framework or pinned versions changed:** deploy the test-framework, update the parent version in [`pom.xml`](pom.xml) if it changed, and rebuild the image (see above).
- **Java version:** change the base image in the [`Dockerfile`](Dockerfile) together with `java-version` in `test-framework-parent` and the exercises.
- **Dependabot** only updates GitHub Actions. Maven and Docker updates are disabled on purpose, as the versions must match the test-framework and the exercises. Dependabot PRs must never be auto-merged.

## Publishing
- Push to `main` (changes outside `.github/` and `*.md`) or a manual run of the workflow publishes `:latest`.
- Tags `vX` publish `:X`.

## Testing locally
Build the image and run an exercise like Jenkins does (non-root user, no network):

```sh
docker build -t artemis-javabuild .
docker run --rm --network none --user 12345:12345 -v "$PWD/<exercise>:/work" -w /work artemis-javabuild mvn -B test
```

`<exercise>` is a test repository with the student submission in `assignment/` and must be writable for that user.
With `RUN_IN_ARTEMIS=true`, the test-framework deletes `test/protocols` after a run, so use a copy of the exercise.

> [!CAUTION]
> This repository is public. Never commit exercise material (tests, protocols, solutions, assignment sheets); `.dockerignore` keeps everything except the sample project out of the image.
