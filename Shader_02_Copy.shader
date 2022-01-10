Shader "Unlit/Shader_02_Copy"
{
    Properties
    {
        _DiffuseIBL("Diffuse IBL", 2D) = "black" {}
        _FoamMask("Foam Mask", 2D) = "white" {}
        [NoScaleOffset][Normal]_FoamNormal("Foam Normal", 2D) = "bump" {}
        _FoamWith("Foam Width", Float) = 0.5
        _FoamOpacity("Foam Edge Opacity", Float) = 0.9
        _WaterHeight("Water Height", 2D) = "gray" {}
        [NoScaleOffset][Normal]_WaterNormal01("Water Normal Main", 2D) = "bump" {}
        [NoScaleOffset][Normal]_WaterNormal02("Water Normal Secondary", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Float) = 0.3
        _DiffuseStrength("Diffuse Strength", Float) = 0.1
        _Color01("Wave Color Main", Color) = (0.5,0.5,0.5)
        _Color02("Wave Color Secondary", Color) = (0,0,0)
        _WaterOpacity("Water Opacity", Range(0,1)) = 0.9
        _FoamColor("Foam Color", Color) = (1,1,1)
        _Depth("Depth", Float) = 0.0
        _DepthPow("Depth Falloff", Float) = 0.1
        _Frequency("Wave Frequency", Float) = 0.4
        _Height("Wave Height", Float) = 1.0
        _Speed("Wave Speed", Float) = 0.5

        _TEST("TEST", Float) = 1
    }

    SubShader
    {
        Tags {
            "Queue" = "Transparent"
            //"RenderType" = "Transparent"
        }

        LOD 100
        
        GrabPass
        {
            "_SceneTexture"
        }

        Pass
        {
            //Blend SrcAlpha OneMinusSrcAlpha
            Cull off
            //Ztest off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            #define TAU = 6.283185307179586476925286766559

            struct appdata
            {
                float2 uv : TEXCOORD0;
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 normal : TEXCOORD1;
                float3 tangent : TEXCOORD2;
                float3 bitangent : TEXCOORD3;
                float4 screenPos : TEXCOORD4;
                float4 vertexWorld : TEXCOORD5;
            };

            sampler2D _DiffuseIBL;
            sampler2D _CameraDepthTexture;
            sampler2D _FoamMask;
            float4 _FoamMask_ST;
            sampler2D _FoamNormal;
            sampler2D _WaterHeight;
            float4 _WaterHeight_ST;
            sampler2D _WaterNormal01;
            sampler2D _WaterNormal02;
            float3 _Color01;
            float3 _Color02;
            float3 _FoamColor;
            float _FoamWith;
            float _FoamOpacity;
            float _Depth;
            float _DepthPow;
            float _Frequency;
            float _Height;
            float _Speed;
            float _NormalStrength;
            float _DiffuseStrength;
            float _WaterOpacity;
            float _TEST;
            sampler2D _SceneTexture;

            v2f vert(appdata v)
            {
                v2f o;

                o.vertexWorld = mul(UNITY_MATRIX_M, v.vertex);

                o.uv = float4(
                    o.vertexWorld.x * _WaterHeight_ST.x + _Time.x * _Speed,
                    o.vertexWorld.z * _WaterHeight_ST.y - _Time.x * _Speed,
                    o.vertexWorld.x * _WaterHeight_ST.x - _Time.x * _Speed,
                    o.vertexWorld.z * _WaterHeight_ST.y
                    );

                float height = tex2Dlod(_WaterHeight, float4(o.uv.xy, 6, 6)) - 0.5;
                o.vertexWorld.y += height * _Height;
                
                o.vertex = mul(UNITY_MATRIX_VP, o.vertexWorld);

                o.normal = UnityObjectToWorldNormal(v.normal);
                o.tangent = UnityObjectToWorldDir(v.tangent.xyz);
                o.bitangent = cross(o.normal, o.tangent) * v.tangent.w * unity_WorldTransformParams.w;
                o.screenPos = ComputeScreenPos(o.vertex);

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float depth = Linear01Depth(tex2Dproj(_CameraDepthTexture, i.screenPos).x) * _ProjectionParams.z;
                float edgeMask = depth - i.screenPos.w;
                float foamMask = tex2D(_FoamMask, i.uv.yz * _FoamMask_ST.xy).x; // sample foam noise texture
                float foamMaskEdge = foamMask >= edgeMask - _FoamWith; // test noise values against the depth
                foamMask = saturate(foamMaskEdge - edgeMask * _FoamOpacity); // sets foam edge opacity falloff
                edgeMask = saturate((edgeMask + _Depth) * _DepthPow); // adjustments for the water depth
                
                // normal
                float3 N = UnpackNormal(tex2D(_WaterNormal01, i.uv.xy));
                float3 N02 = UnpackNormal(tex2D(_WaterNormal02, i.uv.zw * 2));
                N = float3(N.xy + N02.xy, N.z * N02.z); // normal combine (wave normals)
                N = lerp(float3(0, 0, 1), N, _NormalStrength * edgeMask); // normal strength
                float3x3 mTanToWorld = {
                    i.tangent.x, i.bitangent.x, i.normal.x,
                    i.tangent.y, i.bitangent.y, i.normal.y,
                    i.tangent.z, i.bitangent.z, i.normal.z,
                };
                N = normalize(mul(mTanToWorld, N));
                
                float3 V = normalize(_WorldSpaceCameraPos - i.vertexWorld);
                float3 L = _WorldSpaceLightPos0.xyz;
                float3 H = normalize(V + L);

                //float3 refraction = refract(L, N, _TEST);
                float4 refracScreenSample = i.screenPos + float4(N.x, N.z, 0, 0); // using normal to refract texture sample coords
                float4 sceneTex = tex2Dproj(_SceneTexture, refracScreenSample);
                
                //-------------
                float refracDepth = Linear01Depth(tex2Dproj(_CameraDepthTexture, refracScreenSample).x) * _ProjectionParams.z;
                float refracEdgeMask = refracDepth - refracScreenSample.w;
                refracEdgeMask = refracEdgeMask < 0 ? refracEdgeMask * -2 : refracEdgeMask;
                refracEdgeMask = saturate(refracEdgeMask * _DepthPow);
                
                float opacity = max(refracEdgeMask, foamMask) * (1 - _WaterOpacity) + _WaterOpacity;
                //--------------

                float waveMask = dot(N, V) * _DiffuseStrength + (1 - _DiffuseStrength);

                float diffuseMask = saturate(dot(N, L));
                float diffuse = (diffuseMask * _DiffuseStrength + (1 - _DiffuseStrength)) * (dot(L, float3(0, 1, 0)) + 0.5);
                float specular = pow(saturate(dot(N, H)), 200);

                float3 diffuseLight = diffuse * _LightColor0.xyz;
                float3 specularLight = specular * _LightColor0.xyz;

                float3 color = lerp(_Color01, _Color02, waveMask); // albedo: base color
                color = lerp(color, _FoamColor, foamMask); // albedo: foam color
                color = diffuseLight * color + specularLight; // albedo: lighting
                
                color = lerp(float3(sceneTex.xyz), color, opacity);

                //return float4(N, 1);
                //return float4(frac(refracScreenSample).xy, 0, 1);
                return float4(color, 1);

                //return float4(i.screenPos + float4(refraction, 0) * (i.screenPos / i.screenPos.w));
                //return output;
            }
            ENDCG
        }
    }
}
