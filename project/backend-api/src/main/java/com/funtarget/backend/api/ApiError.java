package com.funtarget.backend.api;

import java.time.Instant;

public record ApiError(
    String error,
    String message,
    int status,
    String path,
    Instant time,
    String requestId
) {}
