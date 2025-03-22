// Template for IS tonemapping shaders.
//
// PS
// ISHDRBLENDINSHADER - SHBLEND, TONEMAP
// ISHDRBLENDINSHADERCIN - CINEMATIC, SHBLEND, TONEMAP
// ISHDRBLEDINSHADERCINAM - ALPHAMASK, CINEMATIC, SHBLEND, TONEMAP

#if defined(__INTELLISENSE__)
    #define CINEMATIC
    #define ALPHAMASK
#endif

struct PS_INPUT {
    float2 screenEffectUV : TEXCOORD0;
    float2 blendDestUV : TEXCOORD1;
};

struct PS_OUTPUT {
    float4 finalColor : COLOR0;
};

sampler2D ScreenEffect : register(s0);  // Screen space effect being blended (bloom).
sampler2D BlendDest : register(s1);     // Blend destination (rendered screen).

float4 HDRParam : register(c1);
float3 BlurScale : register(c2);

#ifdef CINEMATIC
    float4 Cinematic : register(c19);   // x: saturation, y: average luminance value, z: contrast, w: brightness
    float4 Tint : register(c20);        // rgb: tint color, a: tint strength
    float4 Fade : register(c22);        // rgb: fade color, a: fade strength
#endif

#ifdef ALPHAMASK
    float4 UseAlphaMask : register(c23);
#endif

// Vanilla uses Rec. 601 luminance coefficients, we use the more precise values.
float luminance(float3 color) {
    return dot(color, float3(0.2116, 0.7152, 0.0722f));
}

float3 ApplyTonemapping(float3 color) {
    // Linearize input color first.
    color = pow(color, 2.2f);

    // Apply curve in between Extended Reinhard and Jodie's Reinhard.
    float maxWhite = 2.0f;  // Conservative value to avoid changing the aesthetics too much. 
    float3 result = color * (1.0 + color / (maxWhite * maxWhite)) / (1.0 + color);
    
    // Delinearize.
    result = pow(result, 1.0f / 2.2f);
    
    // Apply a tiny post-tonemap saturation adjustment
    float luma = luminance(result);
    result = lerp(luma.xxx, result, 1.05);
    
    return result;
}


PS_OUTPUT main(PS_INPUT IN) {
    PS_OUTPUT OUT;

    float4 effect = tex2D(ScreenEffect, IN.screenEffectUV.xy);
    float4 dest = tex2D(BlendDest, IN.blendDestUV.xy);
    
    float blendStrength = 1.0f / max(effect.w, HDRParam.x);
    
    // Blend the post process effect into the screen.
    float3 finalBlend = ((blendStrength * HDRParam.x) * dest.rgb) + max(effect.rgb * blendStrength * 0.5f, 0);
    
    #ifdef CINEMATIC
        float lum = luminance(finalBlend);
        // Blend between grayscale and color based on saturation.    
        finalBlend = lerp(lum.rrr, finalBlend.rgb, Cinematic.x);
        // Blend between saturated image and tinted grayscale based on tint strength.
        finalBlend = lerp(finalBlend.rgb, lum * Tint.rgb, Tint.a);
        // Brightness and contrast.
        finalBlend = Cinematic.w * finalBlend.rgb;
    #endif
    
    // Tonemap.
    finalBlend = ApplyTonemapping(finalBlend.rgb);
    
    #ifdef CINEMATIC
        // Contrast.
        finalBlend = Cinematic.z * (finalBlend.rgb - Cinematic.y) + Cinematic.y;
        // Apply fade (night eye?).
        finalBlend = lerp(finalBlend.rgb, Fade.rgb, Fade.a);
    #endif
    
    #ifdef ALPHAMASK
        // Selective post processing.
        float4 destOffset = tex2D(BlendDest, IN.screenEffectUV.xy);
        finalBlend = lerp(destOffset.rgb, finalBlend.rgb, UseAlphaMask.w);
        finalBlend = (destOffset.a == 0) ? destOffset.rgb : finalBlend;
    #endif
    
    OUT.finalColor.a = BlurScale.z;
    OUT.finalColor.rgb = finalBlend.rgb;
    
    return OUT;
}
