package com.zuhlke.worker.listener;

import com.zuhlke.worker.service.BookStorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

// Consumes compressed book bytes from the broker and delegates persistence to BookStorageService.
// In AWS this listener is replaced by an SQS @SqsListener (Spring Cloud AWS).
@Component
public class BookListener {

    private static final Logger log = LoggerFactory.getLogger(BookListener.class);

    private final BookStorageService storageService;

    public BookListener(BookStorageService storageService) {
        this.storageService = storageService;
    }

    @RabbitListener(queues = "books.compressed")
    public void onMessage(byte[] compressedBook) {
        log.info("Received compressed book ({} bytes), persisting to database", compressedBook.length);
        storageService.save(compressedBook);
    }
}
