package
{
	import com.bit101.components.PushButton;
	import com.bit101.components.Slider;
	import com.bit101.components.Text;
	import com.bit101.components.TextArea;
	
	import flash.display.Graphics;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.events.SampleDataEvent;
	import flash.media.Microphone;
	import flash.ui.Mouse;
	import flash.utils.ByteArray;
	
	[SWF(backgroundColor=0xffffff, height=1000, width=1500, frameRate=64)]
	
	public class FSKModem extends Sprite
	{
		private var nWidth:Number;
		private var nCenter:Number;
		private var nScale:Number;
		private var myGraphics:Graphics;
		private var analysisOverlay:Sprite = new Sprite();
		private var my_mic:Microphone;
		private var count:int = 0;
		private var row:int = 0;
		
		private var _byteArray:ByteArray = new ByteArray();
		private var _overflow:ByteArray = new ByteArray();
		
		private var _bytesPerFrame:uint = 1024;
		
		private var sampleRate:int = 44100;
		private var baud:int = 1225;
		private var freqHigh:int = 7350;
		private var freqLow:int  = 4900;
		private var spb:Number = sampleRate/baud; // 36 samples per bit
		//private var spb:Number = 100; // 36 samples per bit
		private var preCarrierBits:Number = Math.ceil(sampleRate*40/1000/spb); // 49 bits
		private var postCarrierBits:Number = Math.ceil(sampleRate*5/1000/spb); // 6.125 bits => 7 bits
		//private var size = (preCarrierBits + postCarrierBits + 10*utf8.length) * spb;
		

	 	private var myPB:PushButton;
		private var processByteArrayPB:PushButton;
		private var mySlider:Slider;
		private var outPutTA:TextArea;
		private var positionTF:Text
		private var showPositionPB:PushButton;
		
		//private var message:A
		//String()
		
		
		public function FSKModem()
		{
			super();
			addEventListener(Event.ADDED_TO_STAGE, init);
			
			
			//stage.addEventListener(MouseEvent.CLICK,calcFequency);
			
			//addEventListener(Event.ENTER_FRAME, enterFrameHandler);
		
		}

		private function init(e:Event):void{
		
			// support autoOrients
			stage.align = StageAlign.TOP_LEFT;
			stage.scaleMode = StageScaleMode.NO_SCALE;
			nWidth = stage.stageWidth;
			nCenter = stage.stageHeight / 2;
			
			myGraphics = graphics;
			my_mic = Microphone.getMicrophone();
			my_mic.setSilenceLevel(30,20);
			my_mic.rate = 44;
			my_mic.gain = 50;
			my_mic.addEventListener(SampleDataEvent.SAMPLE_DATA, drawSampleData);
			
			myPB = new PushButton(this,50,50,"refresh",refresh);
			processByteArrayPB = new PushButton(this,50,75,"process",processByteArray);
			outPutTA = new TextArea(this,50,115,"");
			outPutTA.width = 800;
			outPutTA.height = 100;
			
			mySlider = new Slider(Slider.HORIZONTAL,this,50,95,handleSlider);
			mySlider.maximum =100;
			mySlider.minimum = 10;
			mySlider.value = nScale = 40;
			
			positionTF = new Text(this,50,250,"0");
			positionTF.width = 100;
			showPositionPB = new PushButton(this,175,250,"show position",showPosition);
			
			this.addChild(analysisOverlay);
			analysisOverlay.graphics.beginFill(0x00ff00);
			
			
			var temp:String = "01000001";
			var tempDec:uint = bin2byte(temp);
			
			outPutTA.text += temp + ": " + tempDec + ":" + String.fromCharCode(tempDec);
		}
		
		private function bin2byte(bin:String):uint {
			var byte:uint = 0;
			
			for(var i:uint = 0; i < 8; i++) {
				byte += uint(bin.charAt(7 - i)) * Math.pow(2,i);
			}
			
			return byte;
		}
		
		private function drawSampleData(eventObject:SampleDataEvent):void 
		{
			
			var myData:ByteArray = eventObject.data;
			//trace("myData.length: " + myData.length);
			//calcFequency(myData);
			
			//--------------------------
			//	Tony Code
			//--------------------------
			
			// write incoming ByteArray to internal ByteArray
			_byteArray.writeBytes(myData);
			_byteArray.position = 0;
			
			calcFequency();
			
			// handle overflow
			if (_byteArray.bytesAvailable > 0)
			{
				// write remaining Bytes into overflow
				_overflow.writeBytes(_byteArray, _byteArray.position);
				// flush main byte array
				_byteArray.clear();
				// write overflow back to the main byte array
				_byteArray.writeBytes(_overflow);
				// move position to 0
				_byteArray.position = 0;
				// flush overflow
				_overflow.clear();
				
				trace("there is " + _byteArray.length + " bytes of data remaing after process",showPosition);
			}
			
			//--------------------------
			//	Tony Code End
			//--------------------------
		}
		
		private function calcFequency():void
		{
			count=0;
			row =2;
			//trace("position: " + _byteArray.position);
			myGraphics.clear();
			myGraphics.lineStyle(0, 0x000000);
			
			myGraphics.moveTo(0, row * nScale*2);
			var nPitch:Number = nWidth / _byteArray.length;
			//trace("there is " + _byteArray.length + " bytes");
			//var packetCounter:int = 0;
			var packetColorIsRed:Boolean = false;
			var previousValue:Number = 0;
			var currentValue:Number = 0;
			var zeroCrossingCount:int = 0;
			var zcSampleCount:int =0; //used to count the number of samples in 2 zero crossings. Use to help calc freq
			var packetSampleCount:int = 0;
			
			var packetCount:int = 0;
			var isProcessing:Boolean = false;
			var cumulativeSamples:int = 0;
			var previousFrequency:Number = 0;
			var currentFrequency:Number = 0;
			var averageFrequency:Number = 0;
			var isFrequencyHigh:Boolean = true;
			var numCrossings:int =0;
			var freqShiftMidPacket:Boolean = false;
			var isMessageStarted:Boolean = false;
			
			while (_byteArray.bytesAvailable > 0) 
			{
				
				currentValue = _byteArray.readFloat();
				zcSampleCount++;
				
				if(previousValue > 0 && currentValue<0){
					zeroCrossingCount++
					numCrossings++
				}else if(previousValue < 0 && currentValue>0){
					zeroCrossingCount++
					numCrossings++
				}
				
				
				if(zeroCrossingCount == 2){
					currentFrequency = 1/(zcSampleCount/44100);
					//outPutTA.text += "current: " + String(currentFrequency) + " previous: " + previousFrequency + " numCrossings: "+numCrossings+ " packetCounter: " +packetCounter + " spb: " + spb +"\n";
					
					if(currentFrequency < 5200 && _byteArray.position > 15000){ // if the frequency is lower then 4200 it is a 0 bit
						if(!isProcessing){ //When processing for the first time look for the first 0bit which signals that the packet is starting
							isProcessing = true;
							packetSampleCount = zcSampleCount;
							myGraphics.lineStyle(0,0x00ff00);
							averageFrequency=currentFrequency;
						};
					}
					if(isProcessing ){
						//freqShiftMidPacket = true
						if(packetSampleCount >= 11){ //Limit the check to more then a couple of samples so that small variations don't cause a premature packet ending
							if(previousFrequency < 6850 && currentFrequency > 7300){ //TODO:: Put the frequency ranges in a variable
								outPutTA.text += "Low to High\n";
								freqShiftMidPacket = true;
								analysisOverlay.graphics.drawCircle(count,currentValue * nScale + (row * nScale*1.2),5);
							}else if(previousFrequency > 7200 && currentFrequency < 6800){
								outPutTA.text += "high to low\n";
								freqShiftMidPacket = true;
								analysisOverlay.graphics.drawCircle(count,currentValue * nScale + (row * nScale*1.2),5);
							}
						}
						//outPutTA.text += "current: " + String(currentFrequency) + " previous: " + previousFrequency + " numCrossings: "+numCrossings+ " packetCounter: " +packetCounter + " spb: " + spb +"\n";
					}
					previousFrequency = currentFrequency;
					zeroCrossingCount =0;
					zcSampleCount =0;
					
				}

				if(isProcessing){

					if(packetSampleCount >= spb || freqShiftMidPacket){
						//outPutTA.text += "reset\n";
						//outPutTA.text += "Packet Conditions current: " + String(currentFrequency) + " previous: " + previousFrequency + " numCrossings: "+numCrossings+ " packetSampleCount: " +packetSampleCount + " spb: " + spb +"\n";
						if(packetColorIsRed){
							myGraphics.lineStyle(0,0x000000);
							packetColorIsRed = false;
						}else{
							myGraphics.lineStyle(0,0xff0000);
							packetColorIsRed = true;
						}
						//outPutTA.text += "crossings: "+ String(zeroCrossingCount) + " samples: "+ String(packetCounter) +" frequency:" + String((zeroCrossingCount/3)/(packetCounter/44100)) +"\n";
						var output:String;
						if(Math.round(averageFrequency) < 6600){
							output ="0"
						}else if(Math.round(averageFrequency) > 7100){
							output ="1"
						}
						/*var freqTF:Text = new Text(analysisOverlay,count,15+(row * nScale*1.2),String(Math.round(currentFrequency))+":"+Math.round(averageFrequency)+ "\n" +freqShiftMidPacket + ":" +output);
						freqTF.width = 60;
						freqTF.height = 40;*/
						packetSampleCount = 0;
						numCrossings = 0;
						averageFrequency = currentFrequency;
						freqShiftMidPacket = false;
						packetCount++

					}else{
						packetSampleCount++;
						averageFrequency = (averageFrequency + currentFrequency)/2
					};
					//previousFrequency = currentFrequency;
				}
				
				previousValue=currentValue;
				
				
				var nX:Number = count;
				var nY:Number = currentValue * nScale + (row * nScale*1.2);
				
				myGraphics.lineTo(nX, nY);
				
				count +=2;
				if(count > stage.stageWidth){
					trace("new row");
					count = 0;
					row++;
					myGraphics.moveTo(0, row * nScale*1.2);
				}
				
			}
			
			
		}
		
		private function enterFrameHandler(e:Event):void
		{
			/*myGraphics.clear();
			myGraphics.lineStyle(1, 0x000000);
			myGraphics.moveTo(0, count*100);
			
			var nPitch:Number = nWidth / _byteArray.length;
			
			if (_byteArray.bytesAvailable >= _bytesPerFrame)
			{
			var i:uint = 0;
			while (i < _bytesPerFrame)
			{
			var nX:Number = _byteArray.position * nPitch;
			var nY:Number = _byteArray.readFloat() * nScale + (count*100);
			myGraphics.lineTo(nX, nY);
			i++;
			}
			}
			
			count++;
			
			// handle overflow
			if (_byteArray.bytesAvailable > 0)
			{
			// write remaining Bytes into overflow
			_overflow.writeBytes(_byteArray, _byteArray.position);
			// flush main byte array
			_byteArray.clear();
			// write overflow back to the main byte array
			_byteArray.writeBytes(_overflow);
			// move position to 0
			_byteArray.position = 0;
			// flush overflow
			_overflow.clear();
			}*/
		}
		
		private function refresh(e:Event):void{
			trace("awesome");
			_byteArray.clear();
			row =0;
			count =0;
			myGraphics.clear();
			analysisOverlay.graphics.clear();
			while(analysisOverlay.numChildren)
			{
				analysisOverlay.removeChildAt(0);
			}
			
		}
		
		private function handleSlider(e:Event):void{
			nScale = mySlider.value;
		}
		
		private function processByteArray(e:Event):void{
			outPutTA.text += "\ntest";
			outPutTA.text += "\n"+_byteArray.length;
			var previous:Number = 0;
			var current:Number = 0;
			for(var i:int = 0; i<_byteArray.length; i++){
				current= _byteArray[i].readFloat();
				outPutTA.text += previous + " "+ current;
				if(previous > 0 && current<0){
					outPutTA.text += "\n+- "+i;
				}else if(previous < 0 && current>0){
					outPutTA.text += "\n-+ " + i;
				}
			}
			previous = current;
		}
		
		private function showPosition(e:Event):void{
		
			var pos:int = int(positionTF.text);
			var r:int = 2 + Math.floor((pos/2)/stage.stageWidth);
			var xpos:int = (pos)%stage.stageWidth;
			outPutTA.text = "r: " +r +" xpos: "+ xpos;
			myGraphics.beginFill(0x00ff00);
			myGraphics.drawCircle(xpos*2,r * nScale*1.2,5);
		}
		//private function calcFequency(ba:ByteArray){
		//myGraphics.clear();
		/*trace("ba.length: " + ba.length);
		myGraphics.lineStyle(0, 0x000000);
		myGraphics.moveTo(0, count*100);
		var nPitch:Number = nWidth / myData.length;
		while (myData.bytesAvailable > 0) 
		{
		var nX:Number = myData.position * nPitch;
		var nY:Number = myData.readFloat() * nScale + (count*100);
		myGraphics.lineTo(nX, nY);
		}
		count++;
		trace(count);
		myData.clear();*/
		/*for(var i:int =0; i<bits.length;i++){
		trace(soundBytes[i].length);
		
		}*/
		//}//
		
	}
}
