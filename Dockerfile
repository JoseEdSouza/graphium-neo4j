FROM maven:3.5.3-jdk-8 AS builder

ARG GRAPHIUM_BRANCH_NAME=master

# fix sources for archived debian stretch
# fix sources for archived debian stretch
RUN echo "deb http://archive.debian.org/debian stretch main" > /etc/apt/sources.list \
    && echo "deb http://archive.debian.org/debian-security stretch/updates main" >> /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install --no-install-recommends -y --allow-unauthenticated openjfx zip \
    && apt-get clean \
    && rm -f /var/lib/apt/lists/*_dists_*

# build graphium dependency
RUN git clone https://github.com/JoseEdSouza/graphium /graphium
RUN cd /graphium && git checkout $GRAPHIUM_BRANCH_NAME && mvn -f pom.xml clean install -DskipTests

COPY . /graphium-neo4j/
RUN mvn -f /graphium-neo4j/pom.xml clean package -DskipTests -Dsource.skip

# Remove module-info.class from Jackson or other libs that might be shaded/included
RUN find /graphium-neo4j -name "*.jar" -exec zip -d {} META-INF/versions/9/module-info.class \; || true



FROM neo4j:3.2.9

RUN apk add --no-cache curl tzdata && \
    rm /var/lib/neo4j/lib/commons-io-2.4.jar && \
    curl -L https://repo1.maven.org/maven2/commons-io/commons-io/2.7/commons-io-2.7.jar -o /var/lib/neo4j/lib/commons-io-2.7.jar && \
    curl -L https://repo1.maven.org/maven2/commons-fileupload/commons-fileupload/1.3.3/commons-fileupload-1.3.3.jar -o /var/lib/neo4j/lib/commons-fileupload-1.3.3.jar

# set default value for heap size configuration
ENV NEO4J_dbms_memory_heap_initial__size="1024m"
ENV NEO4J_dbms_memory_heap_max__size="4096m"

COPY --from=builder /graphium-neo4j/neo4j-server-integration/target/graphium-neo4j-server-integration-*.jar /plugins/
COPY --from=builder /graphium-neo4j/api-neo4j-plugin/target/graphium-api-neo4j-plugin-*.jar /plugins/
COPY --from=builder /graphium-neo4j/routing-neo4j-plugin/target/graphium-routing-neo4j-plugin-*.jar /plugins/
COPY --from=builder /graphium-neo4j/mapmatching-neo4j-plugin/target/graphium-mapmatching-neo4j-plugin-*.jar /plugins/
#COPY ./neo4j-server-integration/target/graphium-neo4j-server-integration-*.jar /plugins/
#COPY ./api-neo4j-plugin/target/graphium-api-neo4j-plugin-*.jar /plugins/
#COPY ./routing-neo4j-plugin/target/graphium-routing-neo4j-plugin-*.jar /plugins/
#COPY ./mapmatching-neo4j-plugin/target/graphium-mapmatching-neo4j-plugin-*.jar /plugins/

COPY ./neo4j-server-integration/doc/neo4j-default/conf/*  /var/lib/neo4j/conf/

COPY --from=builder /graphium/converters/osm2graphium/target/osm2graphium.one-jar.jar /osm2graphium.one-jar.jar
COPY --from=builder /graphium/converters/idf2graphium/target/idf2graphium.one-jar.jar /idf2graphium.one-jar.jar

COPY docker-entrypoint.sh /docker-graphium-entrypoint.sh
ENTRYPOINT ["/sbin/tini", "-g", "--", "/docker-graphium-entrypoint.sh"]