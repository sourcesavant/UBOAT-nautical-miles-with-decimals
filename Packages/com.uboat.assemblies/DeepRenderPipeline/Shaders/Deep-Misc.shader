Shader "Hidden/Deep-Misc"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

	HLSLINCLUDE

        #pragma exclude_renderers gles gles3 d3d11_9x
        #pragma target 4.5

        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

        TEXTURE2D(_CameraDepthTexture);
        SAMPLER(sampler_CameraDepthTexture);
        TEXTURE2D(_AmbientOcclusionTexture);
        SAMPLER(sampler_AmbientOcclusionTexture);
        float3 _AOColor;
        float _RenderViewportScaleFactor;

        float2 TransformStereoScreenSpaceTex(float2 uv, float w)
        {
            return uv * _RenderViewportScaleFactor;
        }

        float2 TransformTriangleVertexToUV(float2 vertex)
        {
            float2 uv = (vertex + 1.0) * 0.5;
            return uv;
        }

        struct AttributesDefault
        {
            float3 vertex : POSITION;
        };

        struct VaryingsDefault
        {
            float4 vertex : SV_POSITION;
            float2 texcoord : TEXCOORD0;
            float2 texcoordStereo : TEXCOORD1;
        #if STEREO_INSTANCING_ENABLED
            uint stereoTargetEyeIndex : SV_RenderTargetArrayIndex;
        #endif
        };

        VaryingsDefault VertDefault(AttributesDefault v)
        {
            VaryingsDefault o;
            o.vertex = float4(v.vertex.xy, 0.0, 1.0);
            o.texcoord = TransformTriangleVertexToUV(v.vertex.xy);

        #if UNITY_UV_STARTS_AT_TOP
            o.texcoord = o.texcoord * float2(1.0, -1.0) + float2(0.0, 1.0);
        #endif

            o.texcoordStereo = TransformStereoScreenSpaceTex(o.texcoord, 1.0);

            return o;
        }

    ENDHLSL

	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
        {
			Name "SSAO Apply"
            Blend Zero OneMinusSrcColor, Zero OneMinusSrcAlpha
			
            HLSLPROGRAM

                #pragma vertex VertDefault
                #pragma fragment Frag

                struct Output
                {
                    float4 gbuffer0 : SV_Target0;
                    float4 gbuffer3 : SV_Target1;
                };

                Output Frag(VaryingsDefault i)
                {
                    float ao = 1.0 - SAMPLE_TEXTURE2D(_AmbientOcclusionTexture, sampler_AmbientOcclusionTexture, i.texcoordStereo).r;
                    Output o;
                    o.gbuffer0 = float4(0.0, 0.0, 0.0, ao);
                    o.gbuffer3 = float4(ao * _AOColor, 0.0);
                    return o;
                }

            ENDHLSL
        }

        Pass
        {
			Name "Copy Transparent Background"
            Blend Off
			
            HLSLPROGRAM

                #pragma vertex VertDefault
                #pragma fragment Frag

                TEXTURE2D(_SourceTex);
                SAMPLER(sampler_SourceTex);

                float4 Frag(VaryingsDefault i) : SV_Target
                {
                    float3 src = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, i.texcoordStereo);
                    return float4(src, 0.0);
                }

            ENDHLSL
        }
	}
}
