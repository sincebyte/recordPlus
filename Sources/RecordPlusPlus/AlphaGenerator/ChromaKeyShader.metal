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
    float windowX;
    float windowY;
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

float3 keyColor = config.keyColor.rgb;

    int2 srcPos = int2(gid) - int2(config.windowX, config.windowY);
    float4 srcColor;
    if (srcPos.x >= 0 && srcPos.x < int(config.contentWidth) &&
        srcPos.y >= 0 && srcPos.y < int(config.contentHeight)) {
        srcColor = inTexture.read(uint2(srcPos));
    } else {
        srcColor = config.keyColor;
    }

    float alpha;
    float dist = length(srcColor.rgb - keyColor);
    if (dist < config.thresholdLow) {
        alpha = 0.0;
    } else if (dist > config.thresholdHigh) {
        alpha = 1.0;
    } else {
        alpha = (dist - config.thresholdLow) / (config.thresholdHigh - config.thresholdLow);
    }

    float3 desaturated = srcColor.rgb;
    if (config.spillSuppression > 0.0 && alpha < 1.0) {
        float spill = max(0.0, (1.0 - alpha) * config.spillSuppression);
        float3 corrected = srcColor.rgb - keyColor * spill;
        float3 gray = float3(dot(corrected, float3(0.299, 0.587, 0.114)));
        desaturated = mix(corrected, gray, config.spillSuppression * (1.0 - alpha));
    }

    float3 finalColor = desaturated * alpha;
    float finalAlpha = alpha;

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
                    int2 nSrc = ngid - int2(config.windowX, config.windowY);
                    float nDist;
                    if (nSrc.x >= 0 && nSrc.x < int(config.contentWidth) &&
                        nSrc.y >= 0 && nSrc.y < int(config.contentHeight)) {
                        nDist = length(inTexture.read(uint2(nSrc)).rgb - keyColor);
                    } else {
                        nDist = 0.0;
                    }
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
                        int2 nSrc = ngid - int2(config.windowX, config.windowY);
                        float nDist;
                        if (nSrc.x >= 0 && nSrc.x < int(config.contentWidth) &&
                            nSrc.y >= 0 && nSrc.y < int(config.contentHeight)) {
                            nDist = length(inTexture.read(uint2(nSrc)).rgb - keyColor);
                        } else {
                            nDist = 0.0;
                        }
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