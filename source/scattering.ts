import vertexCode from './shaders/quad.vert.wgsl?raw'
import fragCode from './shaders/scattering.frag.wgsl?raw'

async function initWebGPU(canvas: HTMLCanvasElement) {
    if (!navigator.gpu)
        throw new Error('WebGPU is not supported')

    const adapter = await navigator.gpu.requestAdapter({
        powerPreference: 'high-performance'
    })

    if (!adapter)
        throw new Error('Adapter is not found')

    const device = await adapter.requestDevice()
    const context = canvas.getContext('webgpu') as GPUCanvasContext
    const presentationFormat = navigator.gpu.getPreferredCanvasFormat()
    const devicePixelRatio = window.devicePixelRatio || 1

    canvas.width = canvas.clientWidth * devicePixelRatio
    canvas.height = canvas.clientHeight * devicePixelRatio

    context.configure({
        device: device, 
        format: presentationFormat,
        alphaMode: 'premultiplied'
    })

    return {device, context, presentationFormat}
}

async function initPipeline(device: GPUDevice, format: GPUTextureFormat) {
    let fragmentShader = device.createShaderModule({
        code: fragCode
    })
    
    let compilationInfo = await fragmentShader.getCompilationInfo()

    for (let message of compilationInfo.messages) {
        let formattedMessage = '';

        if (message.lineNum) {
            formattedMessage += `Line ${message.lineNum}:${message.linePos} - ${fragCode.substring(message.offset, message.length)}\n`;
        }

        formattedMessage += message.message;
        
        switch (message.type) {
            case 'error':
            console.error(formattedMessage); break;
            case 'warning':
            console.warn(formattedMessage); break;
            case 'info':
            console.log(formattedMessage); break;
        }
    }

    let pipeline = await device.createRenderPipelineAsync({
        layout: 'auto',
        vertex: {
          module: device.createShaderModule({
            code: vertexCode
          }),
          entryPoint: 'main'
        },
        fragment: {
          module: fragmentShader,
          entryPoint: 'main',
          targets: [
            {
              format: format
            }
          ]
        },
        primitive: {
          topology: 'triangle-list'
        }
    })

    let uniformBuffer = device.createBuffer({
        size: 4 * 4,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    })

    const dayResponse = await fetch(new URL('textures/earth-day.jpg', import.meta.url).toString())
    const nightResponse = await fetch(new URL('textures/earth-night.jpg', import.meta.url).toString())
    
    const dayBitmap = await createImageBitmap(await dayResponse.blob())
    const nightBitmap = await createImageBitmap(await nightResponse.blob())

    let dayTexture = device.createTexture({
        size: [dayBitmap.width, dayBitmap.height, 1],
        format: 'rgba8unorm',
        usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT
    })

    device.queue.copyExternalImageToTexture(
        { source: dayBitmap },
        { texture: dayTexture },
        [dayBitmap.width, dayBitmap.height]
    )

    let nightTexture = device.createTexture({
        size: [nightBitmap.width, nightBitmap.height, 1],
        format: 'rgba8unorm',
        usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT
    })

    device.queue.copyExternalImageToTexture(
        { source: nightBitmap },
        { texture: nightTexture },
        [nightBitmap.width, nightBitmap.height]
    )

    const daySampler = device.createSampler({
        magFilter: 'linear',
        minFilter: 'linear',
        addressModeU: 'clamp-to-edge',
        addressModeV: 'clamp-to-edge'
    })

    const nightSampler = device.createSampler({
        magFilter: 'linear',
        minFilter: 'linear',
        addressModeU: 'clamp-to-edge',
        addressModeV: 'clamp-to-edge'
    })

    const uniformBindGroup = device.createBindGroup({
        layout: pipeline.getBindGroupLayout(0),
        entries: [
        {
            binding: 0,
            resource: {
                buffer: uniformBuffer
            }
        },
        {
            binding: 1,
            resource: daySampler
        },
        {
            binding: 2,
            resource: dayTexture.createView()
        },
        {
            binding: 3,
            resource: nightSampler
        },
        {
            binding: 4,
            resource: nightTexture.createView()
        }]
    });

    return { pipeline, uniformBuffer, uniformBindGroup }
}

var time = 0;

async function run() {
    const canvas = document.querySelector('canvas')

    if (canvas === null)
        throw new Error('Canvas not found')

    const { device, context, presentationFormat } = await initWebGPU(canvas)

    const { pipeline, uniformBuffer, uniformBindGroup } = await initPipeline(device, presentationFormat)

    function frame() {
        let uniforms = new Float32Array(4)
        uniforms[0] = canvas!.width
        uniforms[1] = canvas!.height
        uniforms[2] = time / 500

        time++

        device.queue.writeBuffer(uniformBuffer, 0, uniforms)

        const commandEncoder = device.createCommandEncoder()
        const renderPassDescriptor: GPURenderPassDescriptor = {
            colorAttachments: [{
                view: context.getCurrentTexture().createView(),
                clearValue: { r: 0, g: 0, b: 0, a: 1.0 },
                loadOp: 'clear',
                storeOp: 'store'
            }]
        }

        const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor)
        passEncoder.setPipeline(pipeline)
        passEncoder.setBindGroup(0, uniformBindGroup)
        passEncoder.draw(6)
        passEncoder.end()

        device.queue.submit([commandEncoder.finish()])

        requestAnimationFrame(frame)
    }

    frame()

    /*window.addEventListener('resize', ()=>{
        size.width = canvas.width = canvas.clientWidth * devicePixelRatio
        size.height = canvas.height = canvas.clientHeight * devicePixelRatio
    })*/
}

run()
