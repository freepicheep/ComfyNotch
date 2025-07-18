//
//  lastTalkedTo.c
//  ComfyNotch
//
//  Created by Aryan Rogye on 6/9/25.
//

#include <sqlite3.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "MessageMeta.h"
#include "MessageHashMap.h"
#include "Messages.h"

void preload_hashmap(sqlite3 *db, int64_t last_known_time);
void print_guid(const char *guid, int length);

char *base64_encode(const unsigned char *data, size_t input_length) {
    static const char encoding_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    
    if (input_length == 0) {
        char *empty = malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    
    size_t output_length = 4 * ((input_length + 2) / 3);
    char *encoded_data = malloc(output_length + 1);
    if (!encoded_data) return NULL;
    
    size_t i = 0, j = 0;
    
    // Process 3-byte chunks efficiently
    while (i + 2 < input_length) {
        uint32_t triple = (data[i] << 16) | (data[i+1] << 8) | data[i+2];
        encoded_data[j++] = encoding_table[(triple >> 18) & 0x3F];
        encoded_data[j++] = encoding_table[(triple >> 12) & 0x3F];
        encoded_data[j++] = encoding_table[(triple >> 6) & 0x3F];
        encoded_data[j++] = encoding_table[triple & 0x3F];
        i += 3;
    }
    
    // Handle remaining 1-2 bytes with padding
    if (i < input_length) {
        uint32_t triple = data[i] << 16;
        if (i + 1 < input_length) triple |= data[i+1] << 8;
        
        encoded_data[j++] = encoding_table[(triple >> 18) & 0x3F];
        encoded_data[j++] = encoding_table[(triple >> 12) & 0x3F];
        encoded_data[j++] = (i + 1 < input_length) ? encoding_table[(triple >> 6) & 0x3F] : '=';
        encoded_data[j++] = '=';
    }
    
    encoded_data[output_length] = '\0';
    return encoded_data;
}

const char *get_last_message_text(sqlite3 *db, long long handle_id) {
    // NOTE: not thread-safe, do not call concurrently
    static char buffer[4096] = {0}; // reuse buffer (not thread-safe)
    memset(buffer, 0, sizeof(buffer));
    
    const char *sql =
    "SELECT text, attributedBody FROM message "
    "WHERE handle_id = ? ORDER BY date DESC LIMIT 1;";
    
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK)
        return NULL;
    
    sqlite3_bind_int64(stmt, 1, handle_id);
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(stmt, 0);
        const void *blob = sqlite3_column_blob(stmt, 1);
        int blobSize = sqlite3_column_bytes(stmt, 1);
        
        if (text && strlen((const char *)text) > 0) {
            strncpy(buffer, (const char *)text, sizeof(buffer) - 1);
        } else if (blob && blobSize > 0) {
            // Base64-encode attributedBody
            const char *prefix = "__BASE64__:";
            strncat(buffer, prefix, sizeof(buffer) - strlen(buffer) - 1);
            
            char *encoded = base64_encode((const unsigned char *)blob, blobSize);
            if (encoded) {
                strncat(buffer, encoded, sizeof(buffer) - strlen(buffer) - 1);
                free(encoded);
            }
        }
    }
    
    sqlite3_finalize(stmt);
    return buffer[0] ? buffer : NULL;
}

int64_t get_last_talked_to(sqlite3 *db, int64_t handle_id) {
    
    //    printf("Fetching last talked to for handle_id: %lld\n", handle_id);
    //    printf("DB: %p\n", db);
    
    sqlite3_stmt *stmt;
    const char *sql = "SELECT date FROM message WHERE handle_id = ? ORDER BY date DESC LIMIT 1;";
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK)
        return -1;
    
    sqlite3_bind_int64(stmt, 1, handle_id);
    
    int64_t result = -1;
    if (sqlite3_step(stmt) == SQLITE_ROW)
        result = sqlite3_column_int64(stmt, 0);
    
    sqlite3_finalize(stmt);
    return result;
}

static bool didLoadHashMap = false;

/// Function will check if the chat db has any changed "chat" from the time then it will check if it is from me/the user or not
int has_chat_db_changed(sqlite3 *db, int64_t last_known_time) {
    sqlite3_stmt *stmt;
    const char *sql = "SELECT guid, date, is_from_me FROM message ORDER BY date DESC LIMIT 1;";
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return 0;
    }
    
    /// Only once at start we will preload the hashmap with the last data
    if (!didLoadHashMap) {
        preload_hashmap(db, last_known_time);
        didLoadHashMap = true;
    }
    
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        int guid_len = sqlite3_column_bytes(stmt, 0);
        char *guidCopy = malloc(guid_len + 1);
        memcpy(guidCopy, sqlite3_column_text(stmt, 0), guid_len);
        guidCopy[guid_len] = '\0';
        
        int64_t date = sqlite3_column_int64(stmt, 1);
        int is_from_me = sqlite3_column_int(stmt, 2);
        
        /// Create a MessageMeta struct to check against the hashmap
        MessageMeta meta = {
            .date = date,
            .isFromMe = is_from_me
        };
        
        MessageMeta *existing = hashmap_get(guidCopy);
        
        if (existing == NULL) {
//            print_guid(guidCopy, guid_len);
            /// NOTE: Uncomment the next lines to see if the message that I sent/recevied is new or not
//            printf("🟢 New message detected: %s\n", guidCopy);
//            printf("Date: %lld, From Me: %d\n", date, is_from_me);
            
            hashmap_put(guidCopy, meta);
            free(guidCopy);
            
            int result = meta.isFromMe ? 0 : 1;
            sqlite3_finalize(stmt);
            return result;
        }
        free(guidCopy);
    }
    
    sqlite3_finalize(stmt);
    return 0;
}

void preload_hashmap(sqlite3 *db, int64_t last_known_time) {
    sqlite3_stmt *stmt;
    const char *sql = "SELECT guid, date, is_from_me FROM message WHERE date > ? LIMIT 50;";
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return;
    }
    
    sqlite3_bind_int64(stmt, 1, last_known_time);
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *guid = (const char *)sqlite3_column_text(stmt, 0);
        int64_t date = sqlite3_column_int64(stmt, 1);
        int is_from_me = sqlite3_column_int(stmt, 2);
        
        MessageMeta meta = {
            .date = date,
            .isFromMe = is_from_me == 1
        };
        
        hashmap_put(guid, meta); // load into your cache
    }
    
    sqlite3_finalize(stmt);
//    printf("Size Of Hashmap: %d\n", getSizeOfBucketsStored());
}

void print_guid(const char *guid, int length) {
    printf("GUID: ");
    for (int i = 0; i < length; i++) {
        printf("%02X", (unsigned char)guid[i]);
    }
    printf("\n");
}
