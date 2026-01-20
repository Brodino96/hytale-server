# v1.1.2

FROM eclipse-temurin:25-jre

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /data

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV JAVA_OPTS="-Xmx2G"
ENV UPDATE_ON_STARTUP="false"
ENV PATCHLINE="release"

EXPOSE 5520/udp

ENTRYPOINT ["/entrypoint.sh"]
