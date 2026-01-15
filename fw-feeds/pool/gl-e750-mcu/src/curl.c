typedef void CURL;
typedef enum {
  dummyOpttion
} CURLoption;

typedef enum {
  dummyCode
} CURLcode;

 CURL *curl_easy_init(void)
{ return 0; }

 CURLcode curl_easy_setopt(CURL *curl, CURLoption option, ...)
{ return 0; }

 CURLcode curl_easy_perform(CURL *curl)
{ return 0; }

 void curl_easy_cleanup(CURL *curl)
{}
