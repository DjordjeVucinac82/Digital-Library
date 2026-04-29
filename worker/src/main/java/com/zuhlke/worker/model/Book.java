package com.zuhlke.worker.model;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "books")
public class Book {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // Compressed binary content of the book (GZIP'd PDF)
    @Lob
    @Column(name = "content", nullable = false)
    private byte[] content;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    public Book() {}

    public Book(byte[] content) {
        this.content = content;
    }

    public Long getId() { return id; }
    public byte[] getContent() { return content; }
    public Instant getCreatedAt() { return createdAt; }
}
