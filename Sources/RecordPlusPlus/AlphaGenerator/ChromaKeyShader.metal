#include <metal_stdlib>
using namespace metal;

struct AlphaConfig {
    float4 keyColor;
    float thresholdLow;
    float thresholdHigh;
    float spillSuppression;
};

kernel void chromaKeyKernel(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant AlphaConfig& config [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) {
        return;
    }

    float4 inColor = inTexture.read(gid);
    float3 keyColor = config.keyColor.rgb;

    float3 diff = inColor.rgb - keyColor;
    float distance = sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z);

    float alpha;
    if (distance < config.thresholdLow) {
        alpha = 0.0;
    } else if (distance > config.thresholdHigh) {
        alpha = 1.0;
    } else {
        alpha = (distance - config.thresholdLow) / (config.thresholdHigh - config.thresholdLow);
    }

    float3 desaturated = inColor.rgb;
    if (config.spillSuppression > 0.0 && alpha < 1.0) {
        float spill = max(0.0, (1.0 - alpha) * config.spillSuppression);
        float3 corrected = inColor.rgb - keyColor * spill;
        float3 gray = float3(dot(corrected, float3(0.299, 0.587, 0.114)));
        desaturated = mix(corrected, gray, config.spillSuppression * (1.0 - alpha));
    }

    outTexture.write(float4(desaturated * alpha, alpha), gid);
}