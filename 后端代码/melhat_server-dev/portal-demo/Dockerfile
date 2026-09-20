FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY ruoyi-admin/target/fdc-admin.jar /app/app.jar
ENTRYPOINT ["java", "-Dfile.encoding=UTF-8", "-jar", "/app/app.jar", "--spring.profiles.active=dev,portal-demo"]
