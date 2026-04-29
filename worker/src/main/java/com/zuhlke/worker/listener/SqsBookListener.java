package com.zuhlke.worker.listener;

import com.zuhlke.worker.service.BookStorageService;
import io.awspring.cloud.sqs.annotation.SqsListener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

// Active in the 'aws' profile (EKS deployment).
//
// Receives an S3 object key from SQS, downloads the compressed bytes,
// persists them to RDS, then deletes the S3 object.
// S3 also has a 1-day lifecycle rule as a safety net if deletion fails.
@Component
@Profile("aws")
public class SqsBookListener {

    private static final Logger log = LoggerFactory.getLogger(SqsBookListener.class);

    private final S3Client s3Client;
    private final BookStorageService storageService;
    private final String bucketName;

    public SqsBookListener(S3Client s3Client,
                            BookStorageService storageService,
                            @Value("${app.s3.bucket-name}") String bucketName) {
        this.s3Client = s3Client;
        this.storageService = storageService;
        this.bucketName = bucketName;
    }

    @SqsListener("${app.sqs.queue-url}")
    public void onMessage(String s3Key) {
        log.info("Received S3 key from SQS: {}", s3Key);

        // Download compressed bytes from S3
        ResponseBytes<GetObjectResponse> response = s3Client.getObjectAsBytes(
            GetObjectRequest.builder()
                .bucket(bucketName)
                .key(s3Key)
                .build()
        );
        byte[] compressedBook = response.asByteArray();
        log.info("Downloaded {} bytes from s3://{}/{}", compressedBook.length, bucketName, s3Key);

        // Persist to RDS
        storageService.save(compressedBook);

        // Delete from S3 — transient storage, not needed after persistence
        s3Client.deleteObject(
            DeleteObjectRequest.builder()
                .bucket(bucketName)
                .key(s3Key)
                .build()
        );
        log.info("Deleted s3://{}/{} after successful persistence", bucketName, s3Key);
    }
}
