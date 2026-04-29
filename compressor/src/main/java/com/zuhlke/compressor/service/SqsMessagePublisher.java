package com.zuhlke.compressor.service;

import io.awspring.cloud.sqs.operations.SqsTemplate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.util.UUID;

// Active in the 'aws' profile (EKS deployment).
//
// SQS has a 256 KB message limit — too small for any real PDF.
// The compressed bytes are stored in S3 instead; only the S3 object key
// is sent to SQS. The worker downloads the bytes and deletes the object.
@Service
@Profile("aws")
public class SqsMessagePublisher implements MessagePublisher {

    private static final Logger log = LoggerFactory.getLogger(SqsMessagePublisher.class);

    private final S3Client s3Client;
    private final SqsTemplate sqsTemplate;
    private final String bucketName;
    private final String queueUrl;

    public SqsMessagePublisher(S3Client s3Client,
                                SqsTemplate sqsTemplate,
                                @Value("${app.s3.bucket-name}") String bucketName,
                                @Value("${app.sqs.queue-url}") String queueUrl) {
        this.s3Client = s3Client;
        this.sqsTemplate = sqsTemplate;
        this.bucketName = bucketName;
        this.queueUrl = queueUrl;
    }

    @Override
    public void publish(byte[] data) {
        String s3Key = "books/" + UUID.randomUUID() + ".gz";

        // Upload compressed bytes to S3
        s3Client.putObject(
            PutObjectRequest.builder()
                .bucket(bucketName)
                .key(s3Key)
                .contentLength((long) data.length)
                .build(),
            RequestBody.fromBytes(data)
        );
        log.info("Uploaded {} bytes to s3://{}/{}", data.length, bucketName, s3Key);

        // Send only the S3 key — the worker resolves the content
        sqsTemplate.send(queueUrl, s3Key);
        log.info("Published S3 key to SQS queue: {}", queueUrl);
    }
}
