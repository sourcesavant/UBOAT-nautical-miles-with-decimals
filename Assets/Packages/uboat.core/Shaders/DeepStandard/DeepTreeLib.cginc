#ifndef DEEP_TREE_INCLUDED
#define DEEP_TREE_INCLUDED

#include "Tessellation.cginc"

#if defined(_TREE_LEAVES) && !defined(_TRANSLUCENCY)
	#define _TRANSLUCENCY
#endif

struct appdata_ctitree {
    float4 vertex : POSITION;
    float4 tangent : TANGENT;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
    float4 texcoord1 : TEXCOORD1;
//    #if !defined(IS_BARK)
    	float3 texcoord2 : TEXCOORD2;
//    #esle
//    	float2 texcoord2 : TEXCOORD2;
//   #endif
    fixed4 color : COLOR0;

    #if defined(CTIBARKTESS)
    //UNITY_VERTEX_INPUT_INSTANCE_ID // does not work, so we have to do it manually
	    #if defined(INSTANCING_ON)
	    	#ifdef SHADER_API_PSSL
    			uint instanceID;
    		#else
				uint instanceID : SV_InstanceID;
			#endif
		#endif
	#else
    	UNITY_VERTEX_INPUT_INSTANCE_ID
    #endif
};

#if defined(GEOM_TYPE_BRANCH) || defined(GEOM_TYPE_BRANCH_DETAIL) || defined(GEOM_TYPE_FROND)
#if !defined(CTIBARKTESS)
	float4 _DetailAlbedoMap_ST;
#endif
#endif

float4 _TerrainLODWind;
//float _FadeOutAllLeaves;
//float _FadeOutWind;

#if defined(_BILLBOARD)
	float3 unity_BillboardSize;
	float _WindStrength;
#endif

#if defined(CTITESS)
	float _Tess;
    float _minDist;
    float _maxDist;
    float _ExtrudeRange;
    float _Displacement;
    float _bendBounds;
    sampler2D _DispTex;
#endif

	float2 _RootSnow;

	half4           _Lux_WaterFloodlevel; // x: cracks / y: puddles / z: wetness darkening / w: wetness smoothness /
	half            _Lux_SnowAmount;
	fixed3          _Lux_SnowColor;
	fixed4          _Lux_SnowSpecColor;
	half3 _Lux_RainfallRainSnowIntensity;

// As we do not include the UnityBuiltin3xTreeLibrary we have to also declare the following params:
fixed3 _TranslucencyColor;
fixed _TranslucencyViewDependency;
half _ShadowStrength;

// As we do not include the TerrainEngine:

UNITY_INSTANCING_BUFFER_START (CTIProperties)
	UNITY_DEFINE_INSTANCED_PROP (float4, _Wind)
#define _Wind_arr CTIProperties
UNITY_INSTANCING_BUFFER_END(CTIProperties)

CBUFFER_START(CTITerrain)
	// trees
	fixed4 _TreeInstanceColor;
	float4 _TreeInstanceScale;
	float4x4 _TerrainEngineBendTree;
	float4 _SquashPlaneNormal;
	float _SquashAmount;
CBUFFER_END

#if defined(_PARALLAXMAP)
	float2 _CTI_TransFade;
#endif


struct LeafSurfaceOutput {
	fixed3 Albedo;
	fixed3 Normal;
	fixed3 Emission;
	fixed Translucency;
	half Specular;
	fixed Gloss;
	fixed Alpha;
};

inline half4 LightingTreeLeaf (LeafSurfaceOutput s, half3 lightDir, half3 viewDir, half atten)
{
	half3 h = normalize (lightDir + viewDir);
	
	half nl = dot (s.Normal, lightDir);
	
	half nh = max (0, dot (s.Normal, h));
	half spec = pow (nh, s.Specular * 128.0) * s.Gloss;
	
	// view dependent back contribution for translucency
	fixed backContrib = saturate(dot(viewDir, -lightDir));
	
	// normally translucency is more like -nl, but looks better when it's view dependent
	backContrib = lerp(saturate(-nl), backContrib, _TranslucencyViewDependency);
	
	fixed3 translucencyColor = backContrib * s.Translucency * _TranslucencyColor;
	
	// wrap-around diffuse
	nl = max(0, nl * 0.6 + 0.4);
	
	fixed4 c;
	/////@TODO: what is is this multiply 2x here???
	c.rgb = s.Albedo * (translucencyColor * 2 + nl);
	c.rgb = c.rgb * _LightColor0.rgb + spec;
	
	// For directional lights, apply less shadow attenuation
	// based on shadow strength parameter.
	#if defined(DIRECTIONAL) || defined(DIRECTIONAL_COOKIE)
	c.rgb *= lerp(1, atten, _ShadowStrength);
	#else
	c.rgb *= atten;
	#endif

	c.a = s.Alpha;
	
	return c;
}

// Expand billboard and modify normal + tangent to fit
inline void ExpandBillboard (in float4x4 mat, inout float4 pos, inout float3 normal, inout float4 tangent)
{
	// tangent.w = 0 if this is a billboard
	float isBillboard = 1.0f - abs(tangent.w);
	// billboard normal
	float3 norb = normalize(mul(float4(normal, 0), mat)).xyz;
	// billboard tangent
	float3 tanb = normalize(mul(float4(tangent.xyz, 0.0f), mat)).xyz;
	pos += mul(float4(normal.xy, 0, 0), mat) * isBillboard;
	normal = lerp(normal, norb, isBillboard);
	tangent = lerp(tangent, float4(tanb, -1.0f), isBillboard);
}

inline float4 Squash(in float4 pos)
{
	float3 planeNormal = _SquashPlaneNormal.xyz;
	float3 projectedVertex = pos.xyz - (dot(planeNormal.xyz, pos.xyz) + _SquashPlaneNormal.w) * planeNormal;
	pos = float4(lerp(projectedVertex, pos.xyz, _SquashAmount), 1);
	return pos;
}

float4 SmoothCurve( float4 x ) {   
	return x * x *( 3.0 - 2.0 * x );   
}
float4 TriangleWave( float4 x ) {   
	return abs( frac( x + 0.5 ) * 2.0 - 1.0 );   
}
float4 SmoothTriangleWave( float4 x ) {   
	return SmoothCurve( TriangleWave( x ) );   
}

// End of declarations formerly covered by TerrainEngine.cginc or UnityBuiltin3xTreeLibrary.cginc




struct Input {

	#if defined(CTIBARKTESS)
		float2 uv_MainTex;
		float2 uv2_DetailAlbedoMap;
	#else
		#if !defined(IS_CTIARRAY)	
			float2 uv_MainTex;
		#else
			float2 uv_MainTexArray;
		#endif
	#endif

	#if defined(_NORMALMAP)
			float3 origNormal;
	#endif

	#if defined(GEOM_TYPE_BRANCH) || defined(GEOM_TYPE_BRANCH_DETAIL) || defined(GEOM_TYPE_FROND)
		float2 ctiuv2_DetailAlbedoMap;
	#endif

//	#if !defined(UNITY_PASS_SHADOWCASTER) && !defined (DEPTH_NORMAL) && !defined(CTIBARKTESS) || defined (DEBUG)
		fixed4 color : COLOR; // color.a = AO
//	#endif
	#if !defined (DEPTH_NORMAL)
		#if UNITY_VERSION < 2017
			#ifdef LOD_FADE_CROSSFADE
			//	CTIBARKTESS needs both – but only screenPos gets setup
				#if defined(CTIBARKTESS)
					float4 screenPos;
				#endif
				half3 ditherScreenPos;
			#endif
		#endif
	#endif
	//UNITY_DITHER_CROSSFADE_COORDS
	#ifdef USE_VFACE
		float FacingSign : FACE;
	#endif

	#if defined (DEBUG)
		float2 my_uv2;
		float3 my_uv3;
	#endif
#if defined(IS_SURFACESHADER)
		//float localHeight;
		float3 worldPos;
	float3 worldNormal;
	INTERNAL_DATA
#endif
};

half3 CTI_UnpackScaleNormal(half4 packednormal, half bumpScale)
{
    half3 normal;
    normal.xy = (packednormal.wy * 2 - 1);
    #if (SHADER_TARGET >= 30)
        // SM2.0: instruction count limitation
        // SM2.0: normal scaler is not supported
        normal.xy *= bumpScale;
    #endif
    normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
    return normal;
}

float4 AfsSmoothTriangleWave( float4 x ) {   
	return (SmoothCurve( TriangleWave( x )) - 0.5) * 2.0;   
}

// see http://www.neilmendoza.com/glsl-rotation-about-an-arbitrary-axis/
// 13fps
float3x3 AfsRotationMatrix(float3 axis, float angle)
{
    //axis = normalize(axis); // moved to calling function
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;

    return float3x3	(	oc * axis.x * axis.x + c,			oc * axis.x * axis.y - axis.z * s,	oc * axis.z * axis.x + axis.y * s,
                		oc * axis.x * axis.y + axis.z * s,	oc * axis.y * axis.y + c,			oc * axis.y * axis.z - axis.x * s,
                		oc * axis.z * axis.x - axis.y * s,	oc * axis.y * axis.z + axis.x * s,	oc * axis.z * axis.z + c);   
}

// Scriptable Render Loop
// 7.7fps
float3 Rotate(/*float3 pivot, */float3 position, float3 rotationAxis, float angle)
{
    //rotationAxis = normalize(rotationAxis); // moved to calling function
    float3 cpa = /*pivot + */rotationAxis * dot(rotationAxis, position/* - pivot*/);
    return cpa + ((position - cpa) * cos(angle) + cross(rotationAxis, (position - cpa)) * sin(angle));
}

// https://twitter.com/SebAaltonen/status/878250919879639040

#define FLT_MAX 3.402823466e+38 // Maximum representable floating-point number
float3 FastSign(float3 x)
{
    return saturate(x * FLT_MAX + 0.5) * 2.0 - 1.0;
}



// Detail bending

#if defined(_TREE_LEAVES)
	#define LEAFTUMBLING 1
	#define USE_VFACE 1
#elif defined(_TREE_BARK)
	#define IS_BARK 1
#endif

#define IS_LODTREE 1
//#define ENABLE_WIND 1

void ApplyTreeEffects(inout FragmentCommonData s, fixed color, inout half3 translucency, inout float occlusion, float2 uv)
{
	s.diffColor = lerp(s.diffColor, (s.diffColor + _HueVariation.rgb) * 0.5, color * _HueVariation.a);

#if defined(_TREE)
	fixed4 trngls = tex2D (_TranslucencyMap, uv);
	translucency = trngls.b * _TranslucencyStrength;
	s.smoothness *= trngls.a;
	occlusion *= trngls.g;
#endif

	/*if (_Lux_SnowAmount > 0.0) {
		float _SnowMultiplier = 1.75;		// move to parameter?
		float _NormalInfluence = 0.3;		// move to parameter?
		float _Snow = 5.0;		// move to parameter?

		half2 normalInfluence = lerp(half2(1,1), half2(s.normalWorld.y, -s.normalWorld.y) /* saturate(s.normalWorld.y + 1) * /, _NormalInfluence.xx);
		half baseSnowAmount = saturate(_Lux_SnowAmount * _SnowMultiplier /* 1.75 * / ) * s.alpha;
		half2 snow = saturate(baseSnowAmount.xx - saturate(half2(1,1) - normalInfluence - baseSnowAmount.xx * 0.25));
		//snow *= trngls.r;
		//BlendValue = saturate ( (CrrentBlendStrength - ( 1.0 - Mask)) / _Sharpness );
		snow = saturate( (snow /*- trngls.rr* /) * _Snow.xx ); // / 20 );
	//  Sharpen snow
		//snow = saturate(snow * 1.0 * (2.0 - _Lux_SnowAmount));
		//snow = smoothstep(0.5, 1, snow);
		s.diffColor = lerp( s.diffColor, _Lux_SnowColor.xyz, snow.xxx);
	//	We need snow on backfaces!
		//s.Translucency = lerp(o.Translucency, o.Translucency * 0.2, saturate(snow.x + snow.y) );
		s.specColor = lerp(s.specColor, _Lux_SnowSpecColor.rgb, snow.xxx);
		s.smoothness = lerp(s.smoothness, _Lux_SnowSpecColor.a, snow.x);
		// Smooth normals a bit
		//s.Normal = lerp(o.Normal, half3(0, 0, 1), snow.xxx * 0.5);
		//s.Occlusion = lerp(o.Occlusion, 1.0, snow.x);
	}*/
}

void CTI_AnimateVertex_DWS( inout VertexInput v, float4 pos, float3 normal, float4 animParams, float3 pivot, float tumbleInfluence, float4 Wind, float packedBranchAxis) {	
	// animParams.x = branch phase
	// animParams.y = edge flutter factor
	// animParams.z = primary factor UV2.x
	// animParams.w = secondary factor UV2.y

	float fDetailAmp = 0.1f;
	float fBranchAmp = 0.3f; // 0.3f;

	//float fade = (_FadeOutWind == 1 && unity_LODFade.x > 0 ) ? unity_LODFade.x : 1.0;
	float fade = 1.0;

//	Add extra animation to make it fit speedtree


	float3 TreeWorldPos = float3(unity_ObjectToWorld[0].w, unity_ObjectToWorld[1].w, unity_ObjectToWorld[2].w);
//	fern issue / this does not seem to fix the problem... / float3 TreeWorldPos = mul(unity_ObjectToWorld, float4(0,0,0,1));
	TreeWorldPos.xyz = abs(TreeWorldPos.xyz * 0.125f);
	float sinuswave = _SinTime.z;
//	float4 vOscillations = AfsSmoothTriangleWave(float4(TreeWorldPos.x + sinuswave , TreeWorldPos.z + sinuswave * 0.8, 0.0, 0.0));

	#if defined (LEAFTUMBLING)
		float shiftedsinuswave = sin(_Time.y * 0.5 + _TimeOffset);
		float4 vOscillations = AfsSmoothTriangleWave(float4(TreeWorldPos.x + sinuswave, TreeWorldPos.z + sinuswave * 0.7, TreeWorldPos.x + shiftedsinuswave, TreeWorldPos.z + shiftedsinuswave * 0.8));
	#else
		float4 vOscillations = AfsSmoothTriangleWave(float4(TreeWorldPos.x + sinuswave, TreeWorldPos.z + sinuswave * 0.7, 0.0, 0.0));
	#endif
	// vOscillations.xz = lerp(vOscillations.xz, 1, vOscillations.xz );
	// x used for main wind bending / y used for tumbling
	float2 fOsc = vOscillations.xz + (vOscillations.yw * vOscillations.yw);
	fOsc = 0.75 + (fOsc + 3.33) * 0.33;

	Wind.w *= fade; 
	Wind.xyz *= fade;

	float absWindStrength = length(Wind.xyz);

	// Phases (object, vertex, branch)
	// float fObjPhase = dot(unity_ObjectToWorld[3].xyz, 1);
	// new
	float fObjPhase = abs ( frac( (TreeWorldPos.x + TreeWorldPos.z) * 0.5 ) * 2 - 1 );
	float fBranchPhase = fObjPhase + animParams.x;
	float fVtxPhase = dot(pos.xyz, animParams.y + fBranchPhase);
	
	// x is used for edges; y is used for branches
	float2 vWavesIn = _Time.yy + float2(fVtxPhase, fBranchPhase );
	// 1.975, 0.793, 0.375, 0.193 are good frequencies
	float4 vWaves = (frac( vWavesIn.xxyy * float4(1.975, 0.793, 0.375, 0.193) ) * 2.0 - 1.0);
	vWaves = SmoothTriangleWave( vWaves );
	float2 vWavesSum = vWaves.xz + vWaves.yw;

//	Tumbling / Should be done before all other deformations
	#if defined (LEAFTUMBLING)

		// pos.w: upper bit = lodfade
		// Separate lodfade and twigPhase: lodfade stored in highest bit / twigphase compressed to 7 bits
		// moved to #ifs

		tumbleInfluence = frac(pos.w * 2.0);

		// Move point to 0,0,0
		pos.xyz -= pivot;

		float tumble = (_TumbleStrength == 0) ? 0 : 1;

		if ( (_TumbleStrength || _LeafTurbulence /*> 0*/) && absWindStrength * tumbleInfluence > 0 ) {
			// _Wind.w is turbulence
			// Add variance to the different leaf planes
		
			// good for palms and bananas - but we do it later
			//	float3 fracs = frac( pivot * 33.3 + animParams.x * frac(fObjPhase) * 0.25 ); //fBranchPhase * 0.1); // + pos.w
			// good for trees	 	
	 		float3 fracs = frac( pivot * 33.3 ); //fBranchPhase * 0.1); // + pos.w
	 		float offset = fracs.x + fracs.y + fracs.z;  ;
			float tFrequency = _TumbleFrequency * (_Time.y /* new */ + fObjPhase * 10 );
			// Add different speeds: (1.0 + offset * 0.25)
			// float4 vWaves1 = SmoothTriangleWave( float4( (tFrequency + offset) * (1.0 + offset * 0.25), tFrequency * 0.75 - offset, tFrequency * 0.05 + offset, tFrequency * 1.5 + offset));
			// less sharp
			float4 vWaves1 = SmoothTriangleWave( float4( (tFrequency + offset) * (1.0 + offset * 0.25), tFrequency * 0.75 + offset, tFrequency * 0.5 + offset, tFrequency * 1.5 + offset));
			// float4 vWaves1 = SmoothTriangleWave( float4( (tFrequency + offset), tFrequency * 0.75 - offset, tFrequency * 0.05 + offset, tFrequency * 2.5 + offset));
			float3 windDir = normalize (Wind.xyz);
			

			#if defined (_EMISSION)
// This was the root of the fern issue: branchAxes slightly varied on different LODs!
				float3 branchAxis = frac( packedBranchAxis * float3(1.0, 256.0f, 65536.0f) );
				branchAxis = branchAxis * 2.0 - 1.0;
branchAxis = normalize(branchAxis);
				// we can do better in case we have the baked branch main axis
				float facingWind = (dot(branchAxis, windDir));
			#else
				float facingWind = (dot(normalize(float3(pos.x, 0, pos.z)), windDir)); //saturate 
			#endif

			float3 windTangent = float3(-windDir.z, windDir.y, windDir.x);
			float twigPhase = vWaves1.x + vWaves1.y + (vWaves1.z * vWaves1.z);
			float windStrength = dot(abs(Wind.xyz), 1) * tumbleInfluence * (1.35 - facingWind) * Wind.w + absWindStrength; // Use abs(_Wind)!!!!!!

		//	turbulence
			#if defined (_EMISSION)
				// if(_LeafTurbulence) {
					float angle =
						// center rotation so the leaves rotate leftwards as well as rightwards according to the incoming waves
						// ((twigPhase + vWaves1.w + fBranchPhase) * 0.2 - 0.5) // not so good to add fBranchPhase here...
						((twigPhase + vWaves1.w ) * 0.25 - 0.5)
						// make rotation strength depend on absWindStrength and all other inputs
						* 4.0 * absWindStrength * _LeafTurbulence * tumbleInfluence * (0.5 + animParams.w) * saturate(lerp(1.0, animParams.y * 8, _EdgeFlutterInfluence))
					;

//branchAxis = normalize(branchAxis); // branch axis should be mostly normalized...
					float3x3 turbulenceRot = AfsRotationMatrix( -branchAxis, angle);
					pos.xyz = mul( turbulenceRot, pos.xyz);
					
					#if defined(_NORMALMAP)
						v.normal = mul( turbulenceRot, v.normal.xyz );
					#endif
					// #else
					//	pos.xyz = Rotate(pos.xyz, -branchAxis, angle);
					// #endif
				//}
			#endif
			
		//	tumbling
			// As used by the debug shader
			#if !defined (EFFECT_HUE_VARIATION)
				//if (_TumbleStrength) {
	//				tumbleInfluence = frac(pos.w * 2.0);
					// + 1 is correct for trees/palm / -1 is correct for fern? allow negative values in the material inspector
					float angleTumble = ( windStrength * (twigPhase + fBranchPhase * 0.25) * _TumbleStrength * tumbleInfluence * fOsc.y );
					
					// windTangent should be normalized
					float3x3 tumbleRot = AfsRotationMatrix( windTangent, angleTumble);
					pos.xyz = mul( tumbleRot, pos.xyz);
					
					#if defined(_NORMALMAP)
						v.normal = mul( tumbleRot, v.normal.xyz );
					#endif
					//#else
					//	pos.xyz = Rotate(pos.xyz, windTangent, angleTumble);
					//#endif
				//}
			#endif
		}
		
	//	crossfade – in case anybody uses it...
//		#if defined(LOD_FADE_CROSSFADE)
//			if (unity_LODFade.x != 0.0 && lodfade == 1.0) {
//				pos.xyz *= unity_LODFade.x;
//			}
//		#endif
	//	fade in/out leave planes
		#if defined(LOD_FADE_PERCENTAGE)
			//float lodfade = ceil(pos.w - 0.51);
			float lodfade = (pos.w > 0.5) ? 1 : 0;
			//lodfade += _FadeOutAllLeaves;
			if (/*unity_LODFade.x < 1.0 && */ lodfade) {
				pos.xyz *= 1.0 - unity_LODFade.x;
			}
		#endif
		// Move point back to origin
		pos.xyz += pivot;
	#endif

//	Preserve Length
	float origLength = length(pos.xyz);

	Wind.xyz *= fOsc.x;

	// Edge (xz) and branch bending (y)
	#if !defined(_TREE_BARK)
		float3 bend = animParams.y * fDetailAmp * normal.xyz
		#if !defined(USE_VFACE)
			* FastSign(normal)
		#endif
		;
		// Old style turbulence // bend.y = (animParams.w + animParams.y * _LeafTurbulence) * fBranchAmp;
		bend.y = (animParams.y + animParams.w) * fBranchAmp;
	#else
		float3 bend = float3(0,0,0);
		bend.y = (animParams.w) * fBranchAmp;
	#endif



	// This gets never zero even if there is no wind. So we have to multiply it by length(Wind.xyz)
	// if not disabled in debug shader
	#if !defined(EFFECT_BUMP)
		// this is still fucking sharp!!!!!
		pos.xyz += ( ((vWavesSum.xyx * bend) + (Wind.xyz * vWavesSum.y * animParams.w)) * Wind.w) * absWindStrength;
	#endif

//	Preserve Length
	// Doing it 2 times might help though
	// pos.xyz = normalize(pos.xyz) * origLength;

//	Primary bending / Displace position
	#if !defined (ENABLE_WIND)
		pos.xyz += animParams.z * Wind.xyz;
	#endif

//	Preserve Length
	#if defined(LOD_FADE_PERCENTAGE) && defined (LEAFTUMBLING)
		pos.xyz = lerp(normalize(pos.xyz) * origLength, pos.xyz, lodfade * (unity_LODFade.x) )  ;
	#else
		pos.xyz = normalize(pos.xyz) * origLength;
	#endif
	v.vertex.xyz = pos.xyz;

//	Store Variation
	#if !defined(UNITY_PASS_SHADOWCASTER) && defined (IS_LODTREE) && !defined (DEBUG)
		v.color.r = saturate ( ( frac(TreeWorldPos.x + TreeWorldPos.y + TreeWorldPos.z) + frac( (TreeWorldPos.x + TreeWorldPos.y + TreeWorldPos.z) * 3.3 ) ) * 0.5 );
	#endif
}

#if defined(_BILLBOARD)
void AFSBillboardVert_DWS (inout VertexInput v) {

	float4 position = v.vertex;
	float3 worldPos = v.vertex.xyz + float3(unity_ObjectToWorld[0].w, unity_ObjectToWorld[1].w, unity_ObjectToWorld[2].w);
//	float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

	// Add some kind of self shadowing when looking against sun
	// might need some more love - and looks weird in forward
//	#if defined(UNITY_PASS_SHADOWCASTER)
//		float offset = saturate(1.0 - saturate( dot(normalize(worldPos - _WorldSpaceCameraPos ), _WorldSpaceLightPos0.xyz) ) * 2.0); // ok
//		position.xz -= _WorldSpaceLightPos0.xz * saturate(offset) * _ShadowOffset;
//	#endif

	// Store Color Variation
	#if !defined(UNITY_PASS_SHADOWCASTER)
		float3 TreeWorldPos = abs(worldPos.xyz * 0.125f);
		v.color.r = saturate((frac(TreeWorldPos.x + TreeWorldPos.y + TreeWorldPos.z) + frac((TreeWorldPos.x + TreeWorldPos.y + TreeWorldPos.z) * 3.3)) * 0.5);
	#endif

// 	////////////////////////////////////
//	Set vertex position
	#if defined(UNITY_PASS_SHADOWCASTER)
		// We have to distinguish between depth and shadows (forward)
		// this is 0.0 while rendering the shadows but something else when unity renders depth
		float testShadowcasterPass = unity_BillboardCameraPosition.x + unity_BillboardCameraPosition.y + unity_BillboardCameraPosition.z;

		#if defined (SHADOWS_CUBE) || defined (SPOT)
			float3 eyeVec = (testShadowcasterPass == 0.0) ? normalize(_WorldSpaceLightPos0.xyz - worldPos) : normalize(_WorldSpaceCameraPos - worldPos);
		#else
			float3 eyeVec = (testShadowcasterPass == 0.0) ? -_WorldSpaceLightPos0.xyz : normalize(_WorldSpaceCameraPos - worldPos);
		#endif
	#else
		float3 eyeVec = normalize(_WorldSpaceCameraPos - worldPos);
	#endif

	float3 billboardTangent = normalize(float3(-eyeVec.z, 0, eyeVec.x));
	float3 billboardNormal = float3(billboardTangent.z, 0, -billboardTangent.x);	// cross({0,1,0},billboardTangent)

	float2 percent = v.uv0.xy;
	float3 billboardPos = (percent.x - 0.5) * unity_BillboardSize.x * v.uv1.x * billboardTangent;

	billboardPos.y += (percent.y * unity_BillboardSize.y * 2.0 + unity_BillboardSize.z) * v.uv1.y * _TreeHeightLimit;

	position.xyz += billboardPos;
	v.vertex.xyz = position.xyz;
	v.vertex.w = 1.0f;

//	Wind
	#if defined(_EMISSION)
		worldPos.xyz = abs(worldPos.xyz * 0.125f);
		float sinuswave = _SinTime.z;
		float4 vOscillations = AfsSmoothTriangleWave(float4(worldPos.x + sinuswave, worldPos.z + sinuswave * 0.8, 0.0, 0.0));
		float fOsc = vOscillations.x + (vOscillations.y * vOscillations.y);
		fOsc = 0.75 + (fOsc + 3.33) * 0.33;
		//v.vertex.xyz += _TerrainLODWind.xyz * fOsc * pow(percent.y, 1.5);			// pow(y,1.5) matches the wind baked to the mesh trees
	
	//	Needed since Unity 5.4., needed in Unity 5.5. as well. Not needed since 5.6. anymore
	//	Detect single billboards which seem to have a very special unity_ObjectToWorld matrix and get corrupted by wind

	 	#if (UNITY_VERSION >= 540 && UNITY_VERSION < 560)
			float3 p1 = mul(unity_ObjectToWorld, float4(0,0,0,1)).xyz;
			float3 p2 = mul(unity_ObjectToWorld, float4(0,0,1,1)).xyz;
			float scale = p2.z - p1.z;
			v.vertex.xyz += _WindStrength * _TerrainLODWind.xyz * fOsc * pow(percent.y, 1.5) / scale;	// pow(y,1.5) matches the wind baked to the mesh trees
		#else
			v.vertex.xyz += _WindStrength * _TerrainLODWind.xyz * fOsc * pow(percent.y, 1.5);	// pow(y,1.5) matches the wind baked to the mesh trees
		#endif
	#endif

// 	////////////////////////////////////
//	Get billboard texture coords
	float angle = atan2(billboardNormal.z, billboardNormal.x);						// signed angle between billboardNormal to {0,0,1}
	angle += angle < 0 ? 2 * UNITY_PI : 0;										

/*
//	SpeedTree Billboards seem to have shrinked uvs, so we expand them // padding seems to be 0.05?
	float minmax = v.uv0.x * 2 - 1;
	minmax *= 1.0 / 0.85; // (1.0 - 0.06977); // 0.95
	v.uv0.x = saturate( minmax * 0.5 + 0.5);
//	Adjust texccord to clamped height
	v.uv0.y *= _TreeHeightLimit;
*/

//	Set Rotation
	angle += v.uv1.z;
//	Write final billboard texture coords
	const float invDelta = 1.0 / (45.0 * ((UNITY_PI * 2.0) / 360.0));
	float imageIndex = fmod(floor(angle * invDelta + 0.5f), 8);
	float2 column_row;
	column_row.x = imageIndex * 0.25; // we do not care about the horizontal coord that much as our billboard texture tiles
	//column_row.y = (imageIndex > 3) ? 0 : 0.5;
	column_row.y = saturate(4 - imageIndex) * 0.5;
	v.uv0.xy = column_row + v.uv0.xy * float2(0.25, 0.5);

// 	////////////////////////////////////
//	Set Normal and Tangent
	v.normal = billboardNormal.xyz;

#ifdef _TANGENT_TO_WORLD
	v.tangent = float4(billboardTangent.xyz, -1.0);
#endif

	//v.color.b = saturate( 1.0 - dot(eyeVec, billboardNormal.xyz) );

}
#endif

#endif
