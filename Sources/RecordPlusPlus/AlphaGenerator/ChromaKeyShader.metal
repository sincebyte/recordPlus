#include <metal_stdlib>
using namespace metal;

struct AlphaConfig {
    float4 keyColor;
    float4 borderColor;
    float thresholdLow;
    float thresholdHigh;
    float spillSuppression;
    float cornerRadius;
    float width;
    float height;
    float borderWidth;
    float contentWidth;
    float contentHeight;
};

float roundedRectSDF(float2 p, float2 halfSize, float r) {
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

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

    float2 center = float2(config.width * 0.5, config.height * 0.5);
    float2 halfSize = float2(config.width * 0.5, config.height * 0.5);
    float2 p = float2(gid) - center;
    float d = roundedRectSDF(p, halfSize, config.cornerRadius);

    float cornerMask = 1.0 - smoothstep(-2.0, 1.0, d);
    float contentAlpha = alpha * cornerMask;

    float3 finalColor = desaturated * contentAlpha;
    float finalAlpha = contentAlpha;

    if (config.borderWidth > 0.0 && alpha > 0.5) {
        int bw = max(1, int(config.borderWidth));
        int gap = 1;

        bool skip = false;
        for (int d = 1; d <= gap + 1 && !skip; d++) {
            int2 dirs[4] = { int2(d, 0), int2(-d, 0), int2(0, d), int2(0, -d) };
            for (int i = 0; i < 4 && !skip; i++) {
                int2 ngid = int2(gid) + dirs[i];
                if (ngid.x >= 0 && ngid.x < int(config.width) &&
                    ngid.y >= 0 && ngid.y < int(config.height)) {
                    float4 nColor = inTexture.read(uint2(ngid));
                    float nDist = length(nColor.rgb - keyColor);
                    if (nDist < config.thresholdLow) {
                        skip = true;
                    }
                }
            }
        }

        if (!skip) {
            bool nearBg = false;
            for (int d = gap + 2; d <= gap + 1 + bw && !nearBg; d++) {
                int2 dirs[4] = { int2(d, 0), int2(-d, 0), int2(0, d), int2(0, -d) };
                for (int i = 0; i < 4 && !nearBg; i++) {
                    int2 ngid = int2(gid) + dirs[i];
                    if (ngid.x >= 0 && ngid.x < int(config.width) &&
                        ngid.y >= 0 && ngid.y < int(config.height)) {
                        float4 nColor = inTexture.read(uint2(ngid));
                        float nDist = length(nColor.rgb - keyColor);
                        if (nDist < config.thresholdLow) {
                            nearBg = true;
                        }
                    }
                }
            }
            if (nearBg) {
                finalAlpha = config.borderColor.a;
                finalColor = config.borderColor.rgb;
            }
        }
    }

    outTexture.write(float4(finalColor, finalAlpha), gid);
}