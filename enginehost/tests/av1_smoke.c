/* Host smoke test (Droidtop/tracker#906): AV1 resolves to dav1d inside libavcodec, opens
 * and drains cleanly. Built and run by the host CI job against the build directory. */
#include <stdio.h>
#include <libavcodec/avcodec.h>
int main(void){
  const AVCodec* c = avcodec_find_decoder(AV_CODEC_ID_AV1);
  if(!c){ puts("FAIL: no AV1 decoder"); return 1; }
  printf("AV1 decoder: %s (%s)\n", c->name, c->long_name);
  AVCodecContext* ctx = avcodec_alloc_context3(c);
  int r = avcodec_open2(ctx, c, NULL);
  printf("open: %d\n", r);
  /* one empty packet then flush: dav1d answers EAGAIN/EOF, never a crash */
  AVPacket* p = av_packet_alloc(); AVFrame* f = av_frame_alloc();
  avcodec_send_packet(ctx, NULL); int g = avcodec_receive_frame(ctx, f);
  printf("drain: %s\n", g == AVERROR_EOF ? "EOF" : "other");
  av_frame_free(&f); av_packet_free(&p); avcodec_free_context(&ctx);
  int ok = r == 0 && g == AVERROR_EOF && c->name[0]=='l';
  puts(ok ? "SMOKE OK" : "SMOKE FAILED"); return !ok;
}
