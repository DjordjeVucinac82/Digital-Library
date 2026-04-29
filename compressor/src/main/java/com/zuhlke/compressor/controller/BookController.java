package com.zuhlke.compressor.controller;

import com.zuhlke.compressor.service.CompressorService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

// Receives PDF uploads from the Library Portal and triggers compression + publishing
@RestController
@RequestMapping("/api/books")
public class BookController {

    private final CompressorService compressorService;

    public BookController(CompressorService compressorService) {
        this.compressorService = compressorService;
    }

    @PostMapping("/upload")
    public ResponseEntity<String> upload(@RequestParam("file") MultipartFile file,
                                         @RequestParam("title") String title) {
        compressorService.compressAndPublish(file, title);
        return ResponseEntity.accepted().body("Book accepted for processing: " + title);
    }
}
