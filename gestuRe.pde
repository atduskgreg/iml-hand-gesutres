// TODO:
// * give the user the ability to turn the active mode display off
// * give the user the ability to set the threshold for the active mode display
// * show a progress bar indicating when acttive mode display will appear
// * move probability scores so they're not covered up by active mode

import processing.video.*;
import controlP5.*;

import gab.opencv.*;
import org.opencv.core.Core;
import org.opencv.core.CvType;
import org.opencv.core.Mat;
import org.opencv.core.Scalar;
import org.opencv.core.TermCriteria;

import org.opencv.core.Mat;
import org.opencv.core.MatOfFloat;
import org.opencv.core.MatOfPoint;

import org.opencv.objdetect.HOGDescriptor;

import org.opencv.core.Size;
import org.opencv.core.Scalar;
import org.opencv.core.Core;

import java.util.Map;
import java.util.Arrays;
import java.util.TreeMap;
import java.util.Collection;

Libsvm classifier;
OpenCV opencv;

Capture video;
ControlP5 control;

ArrayList<ArrayList<PImage>> classImages;
ArrayList<Sample> trainingSamples;

int w = 640;
int h = 480;

PImage testImage;
int rectW = 150;
int rectH = 150;

int currentLabel = 0;
boolean trained = false;

int numClasses = 5;

TreeMap<Double, HashMap> sortedClassesSnapshot;
TreeMap<Double, HashMap> sortedClasses;


PImage defaultImage;
double confidenceGap = 1.0;
float confidenceGapThreshold = 0.2;
int timesOverGap = 0; // per second
double secondStarted = 0;
int countThreshold = 25;

boolean activeMode = false;
boolean prevMode = false;
PGraphics activeDisplay;
PImage imageToClassify;

double timePerSuggestion = 1000;
double lastSuggestionAt = 0;
int currentSuggestion = 0;
boolean suggestionAccepted = false;

PFont font;
PFont bold;

boolean activeModeAllowed = true;

void setup() {
  opencv = new OpenCV(this, 50, 50);
  classifier = new Libsvm(this);
  classifier.setNumFeatures(1728);

  video = new Capture(this, w/2, h/2);
  video.start();

  size(750, 600);

  trainingSamples = new ArrayList<Sample>();

  classImages = new ArrayList<ArrayList<PImage>>();
  for (int i = 0; i < numClasses; i++) {
    classImages.add(new ArrayList<PImage>());
  }

  testImage = createImage(50, 50, RGB);
  defaultImage = createImage(50, 50, RGB);
  for (int i = 0; i < defaultImage.pixels.length; i++) {
    defaultImage.pixels[i] = color(0, 255, 0);
  }

  font = loadFont("Helvetica-48.vlw");
  bold = loadFont("Helvetica-Bold-48.vlw");

  imageToClassify = createImage(rectW, rectH, RGB);

  activeDisplay = createGraphics(400, 300);
  control = new ControlP5(this);

  control.addSlider("confidenceGapThreshold")
    .setCaptionLabel("confidence")
      .setPosition(150, 470)
        .setRange(0.0, 1.0)
          .setSize(200, 20).getCaptionLabel().align(0, 0).setHeight(20);

  control.addToggle("activeModeAllowed")
    .setCaptionLabel("active mode allowed?")
      .setPosition(150, 500)
        .setSize(50, 20)
          .setValue(true)
            .setMode(ControlP5.SWITCH);


  control.addSlider("timesOverGap")
    .setCaptionLabel("ask")
      .setPosition(150, 540)
        .setMax(countThreshold)
          .setSize(200, 20).getCaptionLabel().align(0,0).setHeight(10);

  control.addSlider("countThreshold")
    .setCaptionLabel("time before ask")
      .setPosition(150, 570)
        .setValue(countThreshold)
          .setSize(200, 20).getCaptionLabel().align(0, 0).setHeight(20);
}
void controlEvent(ControlEvent theEvent) {
  if (theEvent.isFrom(control.getController("countThreshold"))) {
    countThreshold = (int)control.getController("countThreshold").getValue();
    control.getController("timesOverGap").setMax(countThreshold);
  }
}

void populateActiveDisplay() {
  if (!prevMode && activeMode) {
    imageToClassify.resize(rectW, rectH);
    imageToClassify.copy(video, video.width - rectW - (video.width - rectW)/2, video.height - rectH - (video.height - rectH)/2, rectW, rectH, 0, 0, rectW, rectH);
    lastSuggestionAt = millis();  
    sortedClassesSnapshot = (TreeMap<Double, HashMap>)sortedClasses.clone();
    suggestionAccepted = false;
    currentSuggestion = 0;
    timesOverGap = 0;
  }

  Collection<HashMap> sortedClassImages = sortedClassesSnapshot.values();
  HashMap selectedClass = (HashMap)sortedClassImages.toArray()[currentSuggestion];


  if (suggestionAccepted) {
    Integer classId = (Integer)selectedClass.get("classId");
    println("classifying sample as " + classId);
    classifier.addTrainingSample( new Sample(gradientsForImage( imageToClassify, classId ), classId) );
    classifier.train();
    activeMode = false;
  } 
  else {
    activeDisplay.beginDraw();
    activeDisplay.background(255, 0, 0);
    activeDisplay.noStroke();
    activeDisplay.fill(100);
    activeDisplay.rect(2, 2, activeDisplay.width-4, activeDisplay.height-4);

    activeDisplay.stroke(255);
    activeDisplay.fill(0);
    activeDisplay.textFont(bold, 16);
    activeDisplay.text("PLEASE SELECT A LABEL", 20, 20);

    activeDisplay.textFont(font, 14);

    activeDisplay.text("Tap SPACE when correct label is displayed.", 20, 50);
    activeDisplay.image(imageToClassify, 10, 70);

    if ((millis() - lastSuggestionAt) > timePerSuggestion) {
      currentSuggestion++; 
      if (currentSuggestion > (sortedClassImages.size() - 1)) {
        currentSuggestion = 0;
      }
      lastSuggestionAt = millis();
    }

    activeDisplay.image((PImage)selectedClass.get("image"), 180, 100);  
    activeDisplay.endDraw();
  }
}

void draw() {
  background(0);
  image(video, 0, 0);
  noFill();
  stroke(255, 0, 0);
  strokeWeight(5);
  rect(video.width - rectW - (video.width - rectW)/2, video.height - rectH - (video.height - rectH)/2, rectW, rectH);

  testImage.copy(video, video.width - rectW - (video.width - rectW)/2, video.height - rectH - (video.height - rectH)/2, rectW, rectH, 0, 0, 50, 50);

  smooth();
  textFont(font, 16);

  if (trained) {
    double[] confidence = new double[numClasses];
    double prediction = classifier.predict( new Sample(gradientsForImage(testImage )), confidence);

    sortedClasses = new TreeMap<Double, HashMap>();
    for ( int i = 0; i < confidence.length; i++ ) {
      if (confidence[i] > 0) {
        HashMap map = new HashMap<String, Object>();
        map.put("classId", i);
        if (classImages.get(i).size() > 0) {
          map.put("image", classImages.get(i).get(0) );
          sortedClasses.put( confidence[i], map);
        } 
        else {
          map.put("image", defaultImage );
          sortedClasses.put( confidence[i], map );
        }
      }
    }

    Arrays.sort(confidence);
    confidenceGap = confidence[confidence.length-1] - confidence[confidence.length-2];

    if (millis() - secondStarted > 1000) {
      secondStarted = millis();
      timesOverGap = 0;
    }

    if (confidenceGap < confidenceGapThreshold) {
      timesOverGap++;
    }    

    control.getController("timesOverGap").setValue(timesOverGap);

    text("label: " + prediction, w/2+70, 60);
    image(classImages.get((int)prediction).get(0), w/2+ 70, 0);

    pushMatrix();
    translate(10, h/2 + 80);

    for (Map.Entry entry : sortedClasses.entrySet() ) {
      HashMap h = (HashMap)entry.getValue();
      image((PImage)h.get("image"), 0, 0);
      translate(0, 55);
      double k = (Double)entry.getKey();
      text(nfc((float)k, 2), 55, -40);
    }
    popMatrix();
  }

  text("(a)dd label to: " + currentLabel, 10, h/2 + 20);
  text("(t)rain", 10, h/2+40);

  image(testImage, w/2+ 10, 0);


  pushMatrix();
  translate(w/2 + 160, 0);
  for (int i = 0; i < classImages.size(); i++) {
    pushMatrix();

    translate(i*50, 0);
    if (i == currentLabel) {
      pushStyle();
      noFill();
      stroke(0, 255, 0);
      rect(-5, 0, 55, height);
      popStyle();
    }
    text("C" + i, 0, 15);
    ArrayList<PImage> images = classImages.get(i);
    for (int j = 0; j < images.size(); j++) {
      image(images.get(j), 0, 50*j + 25);
    }
    popMatrix();
  }
  popMatrix();

  prevMode = activeMode;

  if (timesOverGap >= countThreshold) {
    text("TRAIN", w/2 + 10, 60);
    activeMode = true;
  }
  if (!activeModeAllowed) {
    activeMode = false;
  }

  if (activeMode) {
    populateActiveDisplay();
    image(activeDisplay, width/2-activeDisplay.width/2, height/2-activeDisplay.height/2);
  }
}

void keyPressed() {
  if (keyCode == RIGHT) {
    currentLabel++;
    if (currentLabel == numClasses) {
      currentLabel = 0;
    }
  }
  if (keyCode == LEFT) {
    currentLabel--;
    if (currentLabel < 0) {
      currentLabel = numClasses-1;
    }
  }

  if (key == ' ') {
    suggestionAccepted = true;
  }

  if (key == 'a') {
    classifier.addTrainingSample( new Sample(gradientsForImage( testImage, currentLabel ), currentLabel) );
  }

  if (key == 't') {
    classifier.train();
    trained = true;
  }
}

void captureEvent(Capture c) {
  c.read();
}

float[] gradientsForImage(PImage img, int label) {
  img.resize(50, 50);
  img.updatePixels();
  PImage labeledImage = createImage(50, 50, RGB);
  labeledImage.copy(img, 0, 0, 50, 50, 0, 0, 50, 50);
  labeledImage.updatePixels();
  classImages.get(label).add(labeledImage);
  return gradientsForImage(img);
}

float[] gradientsForImage(PImage img) {
  // resize the images to a consistent size:
  opencv.loadImage(img);

  Mat angleMat, gradMat;
  Size winSize = new Size(40, 24);
  Size blockSize = new Size(8, 8);
  Size blockStride = new Size(16, 16);
  Size cellSize = new Size(2, 2);
  int nBins = 9;
  Size winStride = new Size(16, 16);
  Size padding = new Size(0, 0);

  HOGDescriptor descriptor = new HOGDescriptor(winSize, blockSize, blockStride, cellSize, nBins);

  MatOfFloat descriptors = new MatOfFloat();

  //descriptor.compute(opencv.getGray(), descriptors);
  //Size winStride, Size padding, MatOfPoint locations
  MatOfPoint locations = new MatOfPoint();
  descriptor.compute(opencv.getGray(), descriptors, winStride, padding, locations);

  return descriptors.toArray();
}

