"""
Multi-model transcription server with hot-swappable STT providers.
"""

import asyncio
import logging
from pathlib import Path
from aiohttp import web
from typing import Dict, Any

from stt import STT
from llm_processor import LLMProcessor
from config import Config
from whisper_STTProvider import WhisperProvider
from parakeet_STTProvider import ParakeetProvider


class MultiModelTranscriptionServer:
    def __init__(self, config_path: str):
        self.config = Config(config_path)
        self.stt_provider = None
        self.llm = None
        self.logger = logging.getLogger(__name__)
        
    async def initialize_models(self):
        """Load models once at startup."""
        # Get STT configuration
        stt_config = self.config.config.get("stt", {})
        primary_provider = stt_config.get("provider", "whisper")
        
        # Get provider-specific config
        if primary_provider == "whisper":
            provider_config = self.config.whisper
        elif primary_provider == "parakeet":
            provider_config = self.config.parakeet
        else:
            provider_config = {}
        
        # Create STT provider with fallback
        self.logger.info(f"Initializing STT provider: {primary_provider}")
        self.stt_provider = STT.create_provider(primary_provider, provider_config)
        
        # Initialize LLM if enabled
        if self.config.llm.get("enabled", True):
            self.logger.info("Loading LLM processor...")
            self.llm = LLMProcessor(self.config.llm)
        
        self.logger.info("All models loaded successfully")
    
    async def transcribe_handler(self, request):
        """Handle transcription requests."""
        try:
            data = await request.json()
            audio_path = data.get('audio_path')
            provider_override = data.get('provider')  # Allow runtime provider switching # TODO: Think about this feature more
            
            if not audio_path or not Path(audio_path).exists():
                return web.json_response(
                    {'error': 'Invalid audio path'}, 
                    status=400
                )
            
            # Use override provider if specified
            if provider_override and provider_override != self._get_current_provider():
                self.logger.info(f"Switching to provider: {provider_override}")
                provider_config = self._get_provider_config(provider_override)
                self.stt_provider = STT.create_provider(provider_override, provider_config)
            
            # Transcribe with current provider (STT only, no LLM post-processing)
            # LLM refinement is handled separately via /transform endpoint
            transcription = self.stt_provider.transcribe(audio_path)
            
            return web.json_response({
                'transcription': transcription,
                'provider': self._get_current_provider()
            })
            
        except Exception as e:
            self.logger.error(f"Transcription failed: {e}")
            return web.json_response(
                {'error': str(e)}, 
                status=500
            )
    
    def _get_current_provider(self) -> str:
        """Get current provider type."""
        if isinstance(self.stt_provider, WhisperProvider):
            return "whisper"
        elif isinstance(self.stt_provider, ParakeetProvider):
            return "parakeet"
        return "unknown"
    
    def _get_provider_config(self, provider: str) -> Dict[str, Any]:
        """Get configuration for specific provider."""
        if provider == "whisper":
            return self.config.whisper
        elif provider == "parakeet":
            return self.config.parakeet
        return {}
    
    async def providers_handler(self, request):
        """List available providers and their status."""
        providers = {
            "whisper": {
                "available": True,  # Always available (local)
                "description": "Local Whisper model"
            },
            "parakeet": {
                "available": True,  # Always available (local, MLX-optimized)
                "description": "Parakeet MLX model (Apple Silicon optimized)"
            },
        }
        
        return web.json_response({
            'providers': providers,
            'current': self._get_current_provider()
        })
    
    async def switch_provider_handler(self, request):
        """Switch STT provider at runtime."""
        try:
            data = await request.json()
            new_provider = data.get('provider')
            
            if not new_provider:
                return web.json_response(
                    {'error': 'Provider not specified'}, 
                    status=400
                )
            
            provider_config = self._get_provider_config(new_provider)
            self.stt_provider = STT.create_provider(new_provider, provider_config)
            
            return web.json_response({
                'message': f'Switched to {new_provider}',
                'provider': new_provider
            })
            
        except Exception as e:
            return web.json_response(
                {'error': str(e)}, 
                status=500
            )
    
    # Default transform prompts (used when not configured in settings.yaml)
    DEFAULT_TRANSFORM_PROMPTS = {
        'bullets': """Convert the following text into clear, concise bullet points.
Preserve all key details but improve clarity and remove filler words.
Do not add any preamble or explanation - output only the bullet points.
Use "•" as the bullet character.

Text: {text}"""
    }
    
    async def transform_handler(self, request):
        """Transform text using LLM with specified mode."""
        try:
            data = await request.json()
            text = data.get('text')
            mode = data.get('mode', 'bullets')
            
            if not text:
                return web.json_response(
                    {'error': 'No text provided'}, 
                    status=400
                )
            
            # Get transform modes from config, with built-in defaults as fallback
            transform_config = self.config.transform
            modes = transform_config.get('modes', {})
            
            # Check config first, then fall back to built-in defaults
            if mode in modes:
                mode_config = modes[mode]
                prompt_template = mode_config.get('prompt', '{text}')
            elif mode in self.DEFAULT_TRANSFORM_PROMPTS:
                prompt_template = self.DEFAULT_TRANSFORM_PROMPTS[mode]
                self.logger.info(f"Using built-in default prompt for mode: {mode}")
            else:
                available = list(set(modes.keys()) | set(self.DEFAULT_TRANSFORM_PROMPTS.keys()))
                return web.json_response(
                    {'error': f'Unknown transform mode: {mode}. Available: {available}'}, 
                    status=400
                )
            
            if not self.llm:
                return web.json_response(
                    {'error': 'LLM processor not available'}, 
                    status=503
                )
            
            # Create a temporary LLM config with the mode's prompt
            original_prompt = self.llm.config.get('prompt')
            self.llm.config['prompt'] = prompt_template
            
            self.logger.info(f"Transforming text with mode: {mode}")
            transformed = self.llm.process(text)
            
            # Restore original prompt
            self.llm.config['prompt'] = original_prompt
            
            return web.json_response({
                'transformed': transformed,
                'mode': mode
            })
            
        except Exception as e:
            self.logger.error(f"Transform failed: {e}")
            return web.json_response(
                {'error': str(e)}, 
                status=500
            )
        
    async def reload_model_handler(self, request):
        """Reload Whisper model with new configuration without server restart."""
        try:
            data = await request.json()
            
            # Get new Whisper configuration
            new_config = {
                "model": data.get("model", self.config.whisper.get("model", "small")),
                "language": data.get("language", self.config.whisper.get("language", "en")),
                "task": data.get("task", self.config.whisper.get("task", "transcribe")),
                "temperature": data.get("temperature", self.config.whisper.get("temperature", 0.0))
            }
            
            self.logger.info(f"Reloading Whisper model with new config: {new_config}")
            
            # Update the config in memory
            self.config.whisper.update(new_config)
            
            # Reload the Whisper provider with new configuration
            if isinstance(self.stt_provider, WhisperProvider):
                # Create new WhisperProvider with updated config
                self.stt_provider = WhisperProvider(new_config)
                self.logger.info("Whisper model reloaded successfully")
            else:
                # If current provider is not Whisper, switch to it
                self.stt_provider = WhisperProvider(new_config)
                self.logger.info("Switched to Whisper provider with new configuration")
            
            return web.json_response({
                'message': 'Model reloaded successfully',
                'config': new_config,
                'provider': 'whisper'
            })
            
        except Exception as e:
            self.logger.error(f"Failed to reload model: {e}")
            return web.json_response(
                {'error': str(e)}, 
                status=500
            )


async def create_app(config_path: str) -> web.Application:
    server = MultiModelTranscriptionServer(config_path)
    await server.initialize_models()
    
    app = web.Application()
    app.router.add_post('/transcribe', server.transcribe_handler)
    app.router.add_post('/transform', server.transform_handler)
    app.router.add_get('/providers', server.providers_handler)
    app.router.add_post('/switch_provider', server.switch_provider_handler)
    app.router.add_post('/reload_model', server.reload_model_handler)
    app.router.add_get('/health', lambda r: web.json_response({'status': 'healthy'}))
    
    return app


async def main():
    """Main entry point for the server."""
    import argparse
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Transcription Server')
    parser.add_argument('config_path', nargs='?', default='settings.yaml',
                       help='Path to configuration file')
    parser.add_argument('--host', default='localhost', help='Host to bind to')
    parser.add_argument('--port', type=int, default=3001, help='Port to bind to (0 chooses a free port)')
    
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Create and start server
    app = await create_app(args.config_path)
    runner = web.AppRunner(app)
    await runner.setup()
    
    site = web.TCPSite(runner, args.host, args.port)
    await site.start()
    
    # Resolve the actual port (useful when 0 was passed)
    # Note: aiohttp's TCPSite does not directly expose the chosen port; keep the CLI port for log parity
    print(f"🚀 Transcription server started on http://{args.host}:{args.port}")
    print("📋 Available endpoints:")
    print("  POST /transcribe      - Transcribe audio file")
    print("  POST /transform       - Transform text with LLM (modes: bullets, etc.)")
    print("  GET  /providers       - List available providers")
    print("  POST /switch_provider - Switch STT provider")
    print("  POST /reload_model    - Reload Whisper model")
    print("  GET  /health          - Health check")
    print("\n💡 Test with Postman:")
    print("  POST http://localhost:8080/transcribe")
    print("  Body: {\"audio_path\": \"/path/to/audio.wav\"}")
    print("\n  POST http://localhost:8080/transform")
    print("  Body: {\"text\": \"your text here\", \"mode\": \"bullets\"}")
    
    # Keep server running
    try:
        await asyncio.Future()  # run forever
    except KeyboardInterrupt:
        print("\n🛑 Shutting down server...")
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
