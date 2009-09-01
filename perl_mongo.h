/*
 *  Copyright 2009 10gen, Inc.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#ifndef PERL_MONGO_H
#define PERL_MONGO_H

#define PERL_GCC_BRACE_GROUPS_FORBIDDEN

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define PERL_MONGO_CALL_BOOT(name)  perl_mongo_call_xs (aTHX_ name, cv, mark)

#define OID_CLASS "MongoDB::OID"

/* whether to add an _id field */
#define PREP 1
#define NO_PREP 0

#define INT_32 4
#define INT_64 8
#define DOUBLE_64 8
#define BYTE_8 1
#define OID_SIZE 12

#define BSON_DOUBLE 1
#define BSON_STRING 2
#define BSON_OBJECT 3
#define BSON_ARRAY 4
#define BSON_BINARY 5
#define BSON_UNDEF 6
#define BSON_OID 7
#define BSON_BOOL 8
#define BSON_DATE 9
#define BSON_NULL 10
#define BSON_REGEX 11
#define BSON_DBREF 12
#define BSON_CODE__D 13
#define BSON_CODE 15
#define BSON_INT 16
#define BSON_TIMESTAMP 17
#define BSON_LONG 18
#define BSON_MINKEY -1
#define BSON_MAXKEY 127

#define GROW_SLOWLY 1048576

typedef struct {
  char *start;
  char *pos;
  char *end;
} buffer;

#define BUF_REMAINING (buf->end-buf->pos)
#define set_type(buf, type) serialize_byte(buf, (char)type)
#define serialize_null(buf) serialize_byte(buf, (char)0)
#define serialize_bool(buf, b) serialize_byte(buf, (char)b)

void perl_mongo_call_xs (pTHX_ void (*subaddr) (pTHX_ CV *cv), CV *cv, SV **mark);
SV *perl_mongo_call_reader (SV *self, const char *reader);
SV *perl_mongo_call_method (SV *self, const char *method, int num, ...);
void perl_mongo_attach_ptr_to_instance (SV *self, void *ptr);
void *perl_mongo_get_ptr_from_instance (SV *self);
SV *perl_mongo_construct_instance (const char *klass, ...);
SV *perl_mongo_construct_instance_va (const char *klass, va_list ap);
SV *perl_mongo_construct_instance_with_magic (const char *klass, void *ptr, ...);

void perl_mongo_oid_create(char* twelve, char *twenty4);

// serialization
SV *perl_mongo_bson_to_sv (const char *oid_class, buffer *buf);
void perl_mongo_sv_to_bson (buffer *buf, SV *sv, int add_oid);

void serialize_size(char*, buffer*);
inline void serialize_double(buffer*, double);
inline void serialize_string(buffer*, const char*, int);
inline void serialize_long(buffer*, long long);
inline void serialize_int(buffer*, int);
inline void serialize_byte(buffer*, char);
inline void serialize_bytes(buffer*, const char*, int);

#endif
