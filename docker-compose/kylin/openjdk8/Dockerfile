# 麒麟 V10 系统
FROM hxsoong/kylin:v10-sp3

RUN yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel \
    && yum clean all

ENV JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
ENV PATH=${JAVA_HOME}/bin:${PATH}

WORKDIR /app

CMD ["java", "-version"]
