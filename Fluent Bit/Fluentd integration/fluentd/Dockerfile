FROM fluent/fluentd:latest

USER root

# Install the Azure append-blob plugin (LTS fork recommended)
# You may pin to specific versions if desired.
RUN fluent-gem install fluent-plugin-azure-storage-append-blob-lts --no-document

# Create buffer dir and set ownership with write permissions
RUN mkdir -p /var/log/fluent/buffer && chown -R fluent:fluent /var/log/fluent && chmod -R 775 /var/log/fluent

USER fluent

COPY fluent.conf /fluentd/etc/fluent.conf
