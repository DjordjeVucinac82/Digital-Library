package com.zuhlke.compressor.service;

import io.awspring.cloud.sqs.operations.SqsTemplate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.util.Base64;

// Active in the 'aws' profile (EKS deployment).
// Sends compressed bytes to the SQS queue as a Base64-encoded string.
// SQS messages are text-based, so binary data must be encoded before sending.
@Service
@Profile("aws")
public class SqsMessagePublisher implements MessagePublisher {

    private static final Logger log = LoggerFactory.getLogger(SqsMessagePublisher.class);

    private final SqsTemplate sqsTemplate;
    private final String queueUrl;

    public SqsMessagePublisher(SqsTemplate sqsTemplate,
                                @Value("${app.sqs.queue-url}") String queueUrl) {
        this.sqsTemplate = sqsTemplate;
        this.queueUrl = queueUrl;
    }

    @Override
    public void publish(byte[] data) {
        // Base64-encode before sending — SQS only accepts text payloads
        String encoded = Base64.getEncoder().encodeToString(data);
        sqsTemplate.send(queueUrl, encoded);
        log.info("Published {} bytes (Base64-encoded) to SQS queue: {}", data.length, queueUrl);
    }
}
