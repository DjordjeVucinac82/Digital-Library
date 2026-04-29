package com.zuhlke.worker.listener;

import com.zuhlke.worker.service.BookStorageService;
import io.awspring.cloud.sqs.annotation.SqsListener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.Base64;

// Active in the 'aws' profile (EKS deployment).
// Consumes Base64-encoded compressed book bytes from the SQS queue.
// The compressor sends Base64-encoded data because SQS only supports text payloads.
@Component
@Profile("aws")
public class SqsBookListener {

    private static final Logger log = LoggerFactory.getLogger(SqsBookListener.class);

    private final BookStorageService storageService;

    public SqsBookListener(BookStorageService storageService) {
        this.storageService = storageService;
    }

    // Spring Cloud AWS resolves the queue URL from the property at startup.
    // IRSA provides the credentials — no access keys needed in the pod.
    @SqsListener("${app.sqs.queue-url}")
    public void onMessage(String base64Content) {
        byte[] compressedBook = Base64.getDecoder().decode(base64Content);
        log.info("Received compressed book from SQS ({} bytes), persisting to database",
                compressedBook.length);
        storageService.save(compressedBook);
    }
}
