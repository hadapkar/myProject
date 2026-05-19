# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

# Copy Gradle wrapper + build scripts first for better caching
COPY gradlew gradlew.bat build.gradle settings.gradle ./
COPY gradle gradle

# Windows checkouts can produce CRLF and non-executable wrapper; fix both for Linux builds.
RUN sed -i 's/\r$//' gradlew && chmod +x gradlew

# Download dependencies (will be cached in Docker layer)
RUN ./gradlew --no-daemon dependencies

# Copy source
COPY src src

# Build runnable jar
RUN ./gradlew --no-daemon build

FROM eclipse-temurin:21-jre
WORKDIR /app

ENV PORT=8080
EXPOSE 8080

COPY --from=build /app/build/libs/*.jar /app/app.jar

CMD ["java","-jar","/app/app.jar"]
