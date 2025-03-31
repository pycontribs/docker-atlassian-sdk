FROM redhat/ubi9

# Set default SDK version
ARG ATLASSIAN_SDK_VERSION=9.1.1

# Install Java 1.8
RUN yum install java-1.8.0-openjdk java-1.8.0-openjdk-devel which -y

# Download and install Atlassian Plugin SDK
RUN curl -L https://maven.artifacts.atlassian.com/com/atlassian/amps/atlassian-plugin-sdk/${ATLASSIAN_SDK_VERSION}/atlassian-plugin-sdk-${ATLASSIAN_SDK_VERSION}.tar.gz -o /tmp/atlassian-plugin-sdk.tar.gz \
  && tar -xzf /tmp/atlassian-plugin-sdk.tar.gz -C /opt \
  && mv /opt/atlassian-plugin-sdk-* /opt/atlassian-plugin-sdk \
  && rm /tmp/atlassian-plugin-sdk.tar.gz

# Add SDK to PATH
ENV PATH="/opt/atlassian-plugin-sdk/bin:${PATH}"
