#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 gooThreshold(float2 position, SwiftUI::Layer layer, float threshold, float smoothness) {
    half4 color = layer.sample(position);
    float edge = max(smoothness, 0.001);
    float alpha = smoothstep(threshold - edge, threshold + edge, float(color.a));
    return half4(color.rgb, half(alpha));
}
