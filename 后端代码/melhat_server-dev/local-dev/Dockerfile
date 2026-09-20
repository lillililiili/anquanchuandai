FROM eclipse-temurin:17-jre-jammy

WORKDIR /app

COPY ruoyi-admin/target/fdc-admin.jar /app/fdc-admin.jar

RUN mkdir -p /data/uploadPath /data/hatfile /data/taskPackageFile

EXPOSE 18084

ENTRYPOINT ["java", "-Dfile.encoding=UTF-8", "-jar", "/app/fdc-admin.jar"]
