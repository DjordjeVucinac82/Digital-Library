package com.zuhlke.worker.listener;

import com.zuhlke.worker.service.BookStorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

// Active in the 'local' profile (docker-compose).
// In AWS (profile=aws), SqsBookListener handles message consumption instead.
@Component
@Profile("local")
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
