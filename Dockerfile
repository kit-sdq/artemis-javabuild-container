FROM maven:3-eclipse-temurin-25

MAINTAINER Dominik Fuchss <dominik.fuchss@kit.edu>

RUN apt-get update && apt-get install -y gnupg && rm -rf /var/lib/apt/lists/*

ENV M2_HOME="/usr/share/maven"
# Local repository baked into the image. The container does not run as root (and the user may have no home), so Maven's
# user.home is fixed to /maven-home: every user reads the same user settings /maven-home/.m2/settings.xml (see below).
# The prefix filter is disabled, as it would still try to fetch /.meta/prefixes.txt from repositories declared in
# dependency POMs.
ENV MAVEN_OPTS="-Dmaven.repo.local=/repo -Duser.home=/maven-home -Daether.remoteRepositoryFilter.prefixes=false"
# A flag that indicates a run in artemis
ENV RUN_IN_ARTEMIS="true"

RUN echo "$LANG -- $LANGUAGE -- $LC_ALL" \
    && curl --version \
    && gpg --version \
    && git --version \
    && mvn --version \
    && java --version \
    && javac --version \
    && mkdir /repo && chmod 777 /repo

ADD . /opt/java-template

# Warm up the local repository with exactly the commands Artemis runs (plain_maven_static phases),
# so that all plugins and their runtime dependencies (surefire providers, SpotBugs, PMD, ...) are cached.
# pom.xml is the same as the exercise test repositories' pom.xml; all versions are pinned by
# edu.kit.kastel.sdq.artemis:test-framework-parent, so exactly these versions are cached.
# The remote-repository tracking files are dropped, so the cached artifacts are usable for any repository id.
RUN cd /opt/java-template \
    && mvn -B clean compile \
    && mvn -B test \
    && mvn -B spotbugs:spotbugs checkstyle:checkstyle pmd:pmd pmd:cpd \
    && find /repo -name '_remote.repositories' -delete \
    && find /repo -name '*.lastUpdated' -delete \
    && chmod -R 777 /repo

# From here on, Maven runs offline: the user settings set <offline>true</offline>, so builds in this container never
# contact Maven Central, GitLab or any other repository, not even for SNAPSHOT updates.
# (<offline> in the global settings.xml does not work, as the user settings override it.)
RUN mkdir -p /maven-home/.m2 && printf '%s\n' \
        '<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"' \
        '          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"' \
        '          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0 https://maven.apache.org/xsd/settings-1.2.0.xsd">' \
        '  <localRepository>/repo</localRepository>' \
        '  <offline>true</offline>' \
        '</settings>' > /maven-home/.m2/settings.xml \
    && chmod 755 /maven-home && chmod 777 /maven-home/.m2 && chmod 644 /maven-home/.m2/settings.xml

# Self-check: the image build fails if anything is missing from the cache.
RUN cd /opt/java-template \
    && mvn -B clean compile \
    && mvn -B test \
    && mvn -B spotbugs:spotbugs checkstyle:checkstyle pmd:pmd pmd:cpd \
    && find /repo ! -perm -o+w -exec chmod a+rwX {} + \
    && cd / && rm -rf /opt/java-template

CMD ["mvn"]
