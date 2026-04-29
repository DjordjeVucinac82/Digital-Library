package com.zuhlke.worker.service;

import com.zuhlke.worker.model.Book;
import com.zuhlke.worker.repository.BookRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class BookStorageService {

    private static final Logger log = LoggerFactory.getLogger(BookStorageService.class);

    private final BookRepository bookRepository;

    public BookStorageService(BookRepository bookRepository) {
        this.bookRepository = bookRepository;
    }

    public void save(byte[] compressedContent) {
        Book book = new Book(compressedContent);
        Book saved = bookRepository.save(book);
        log.info("Book saved with id={}, size={} bytes", saved.getId(), compressedContent.length);
    }
}
