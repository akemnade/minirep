/********************************************************************** 
 minirep - Copyright (C) 2012 - Andreas Kemnade
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 3, or (at your option)
 any later version.
             
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied
 warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
***********************************************************************/
using Gtk;

Builder builder;
int serfd;
StringBuilder strbld;
bool queue_busy;
bool temp_in_queue;
bool zeroing;
string extrudertemp_now;
string bedtemp_now;
double travelrate_factor=1.0;
double feedrate_factor=1.0;
Queue<string> buildqueue;
FileStream cmd_file;
int lineno;
void check_queue()
{
  if (queue_busy)
    return;
  if (buildqueue.is_empty()) {
    if (cmd_file != null) {
      string cmd = null;
      do {
	cmd = cmd_file.read_line();
	if (cmd == null) {
	  cmd_file = null;
	  break;
	}
	lineno++;
	stdout.printf("got line %s\n",cmd);
	size_t epos = Posix.strcspn(cmd,"(;");
	if (epos != cmd.length)
	  cmd=cmd[0:(long)epos];
	//stdout.printf("procssed: %s\n",cmd);
	cmd=cmd.strip();
	//stdout.printf("stripped: %s\n",cmd);
      } while (cmd.length == 0);
      if ((cmd != null) && (cmd.length > 0)) {
	int e = cmd.index_of_char('E');
	// stderr.printf("e at %d\n",e);
	if ((travelrate_factor != 1.0) && (e <= 0)) {
	  // stderr.printf("adjusting trate\n");
	  cmd = adjust_f(cmd, travelrate_factor);
	} else if ((feedrate_factor != 1.0) && (e >= 0)) {
	  // stderr.printf("adjusting frate\n");
	  cmd = adjust_f(cmd, feedrate_factor);
	}
	buildqueue.push_tail(cmd);
	if ((lineno % 10) == 0) {
	  Label l = (Label) builder.get_object("status");
	  l.label = @"processing line $lineno";
	}
      }
      
    }
  }
  if (!buildqueue.is_empty()) {
    string cmd = buildqueue.peek_head();
    stdout.printf("->>> %s\n",cmd);
    Posix.write(serfd,cmd,cmd.length);
    Posix.write(serfd,"\n",1);
    queue_busy = true;
  }
}

string adjust_f(string cmd, double f)
{
  int p = cmd.index_of_char('F');
  int end;
  double fnow;
  string tmp;
 
  if (p<=0)
    return cmd;
  var newstr = new StringBuilder.sized(cmd.length+2);
  p++;
  while(cmd[p] == ' ') {
    p++;
  }
  newstr.append_len(cmd,p);
  end=p;
  while(cmd[end].isdigit() || cmd[end] == '-' || cmd[end] == '.' || cmd[end] == ',') {
    end++;
  }
  tmp = cmd[p:end];
  fnow = double.parse(tmp);
  fnow *= f;
  newstr.append_printf("%.2f",fnow);
  while(cmd[end]!=0) {
    newstr.append_c(cmd[end]);
    end++;
  }
  return newstr.str;
}

void add_cmd(string cmd)
{
  buildqueue.push_tail(cmd);
  check_queue();
  
  stdout.printf("-> %s\n",cmd);
}

void xscaleadj_changed_cb(Adjustment adj)
{
  if (!zeroing)
    add_cmd("G1X%.2f".printf(adj.value));
}

void yscaleadj_changed_cb(Adjustment adj)
{
  if (!zeroing)
    add_cmd("G1Y%.2f".printf(adj.value));
}

void zscaleadj_changed_cb(Adjustment adj)
{
  if (!zeroing)
    add_cmd("G1Z%.2f".printf(adj.value));
}

void fscaleadj_changed_cb(Adjustment adj)
{
  add_cmd("G1F%.0f".printf(adj.value));
}

void xhome_clicked_cb()
{
  add_cmd("G161X");
}

void yhome_clicked_cb()
{
  add_cmd("G161Y");
}

void zhome_clicked_cb()
{
  add_cmd("G161Z");
}

void xzero_clicked_cb()
{
  Adjustment adj=(Adjustment)builder.get_object("xscaleadj");
  add_cmd("G92X0");
  adj.value = 0.0;
  adj.value_changed();
}

void yzero_clicked_cb()
{
  Adjustment adj=(Adjustment)builder.get_object("yscaleadj");
  add_cmd("G92Y0");
  adj.value = 0.0;
  adj.value_changed();
}

void zzero_clicked_cb()
{

  Adjustment adj=(Adjustment)builder.get_object("zscaleadj");
  add_cmd("G92Z0");
  adj.value = 0.0;
  zeroing = true;
  adj.value_changed();
  zeroing = false;
}

void eback10_clicked_cb()
{
  add_cmd("G92E0");
  add_cmd("G1E-10");
}

void eback100_clicked_cb()
{
  add_cmd("G92E0");
  add_cmd("G1E-100");
}

void eforward10_clicked_cb()
{
  add_cmd("G92E0");
  add_cmd("G1E10");
}

void eforward100_clicked_cb()
{
  add_cmd("G92E0");
  add_cmd("G1E100");
}

void check_temp_input(string str)
{
  int start,end;
  bool found_temp=false;
  start=str.index_of("T:");
  if (start>=0) {
    start+=2;
    if (str[start] == ' ')
      start++;
    end=start;
    while(str[end].isdigit() || str[end] == '.' || str[end] == ',' || str[end] == '-') {
      end++;
    }
    extrudertemp_now=str[start:end];
    found_temp=true;
  }
  start=str.index_of("B:");
  if (start>=0) {
    start+=2;
    if (str[start] == ' ')
      start++;
    end=start;
    while(str[end].isdigit() || str[end] == '.' || str[end] == ',' || str[end] == '-') {
      end++;
    }
    bedtemp_now=str[start:end];
    found_temp=true;
  }
  if (found_temp) {
    temp_in_queue=false;
    Label l=(Label)builder.get_object("temp_label");
    l.label = @"Extruder: $extrudertemp_now\nBed: $bedtemp_now";
  }
}

void check_strbld()
{
  string [] strs = strbld.str.split("\n");
  strbld.assign(strs[strs.length-1]);
  for(int i = 0; i < (strs.length-1); i++) {
    stdout.printf("<- %s\n",strs[i]);
    check_temp_input(strs[i]);
    if (strs[i].index_of("ok") >= 0) {
      queue_busy = false;
      buildqueue.pop_head();
      check_queue();
    }
  }
}

void extrudertemp_changed_cb(ComboBoxEntry box)
{
  string temp = box.get_active_text();
  int t = int.parse(temp);
  if (t<265) {
    add_cmd(@"M104 S$t");
  }
}

void bedtemp_changed_cb(ComboBoxEntry box)
{
  string temp = box.get_active_text();
  int t = int.parse(temp);
  if (t<111) {
    add_cmd(@"M104 P1 S$t");
  }
}

bool ser_read(IOChannel src, IOCondition condition)
{
  char b[64];
  ssize_t l=Posix.read(serfd,b,b.length-1);
  if (l<=0)
    return false;
  b[l]=0;
  strbld.append((string)b);
  if (b[Posix.strcspn((string)b,"\r\n")] != 0) {
    check_strbld();
  }
  return true;
}

void load_dlg_ok()
{
  FileChooserDialog fc = (FileChooserDialog) builder.get_object("load_dialog");
  string fname = fc.get_filename();;
  stderr.printf("open %s\n",fname);
  cmd_file = FileStream.open(fname, "r");
  lineno=0;
  check_queue();
  fc.hide();
}

void load_dlg_close()
{
  FileChooserDialog fc = (FileChooserDialog) builder.get_object("load_dialog");
  fc.hide();

}

void load_cb()
{
  FileChooserDialog fc = (FileChooserDialog) builder.get_object("load_dialog");
  fc.show();
}

bool temp_poll()
{
  if (!temp_in_queue) {
    add_cmd("M105P0");
    add_cmd("M105");
  }
  temp_in_queue=true;
  return true;
}

void feedrateadj_changed_cb(Adjustment adj)
{
  feedrate_factor = adj.value / 100.0;
  if (feedrate_factor < 0.25)
    feedrate_factor = 0.25;
  stderr.printf("change feedrate to %f\n",feedrate_factor);
}

void travelrateadj_changed_cb(Adjustment adj)
{
  travelrate_factor = adj.value /100.0;
  if (travelrate_factor <0.25)
    travelrate_factor = 0.25;
  stderr.printf("changed trate to %f\n",travelrate_factor);
}

void printstop_cb()
{
  cmd_file = null;
}

int main(string [] args)
{
  Gtk.init(ref args);
  cmd_file = null;
  strbld = new StringBuilder();
  serfd = -1;
  if (args.length > 1)
    serfd = Posix.open(args[1],Posix.O_RDWR);
  if (serfd<0)
    return 1;
  Intl.setlocale(LocaleCategory.NUMERIC, "C");
  temp_in_queue = false;
  queue_busy = false;
  zeroing = false;
  buildqueue = new Queue<string>();
  builder = new Builder();
  builder.add_from_file("minirep.glade");
  builder.connect_signals(null);
  var iocr = new IOChannel.unix_new(serfd);
  iocr.add_watch(GLib.IOCondition.IN,ser_read);
  extrudertemp_now = "";
  bedtemp_now = "";
  Timeout.add(2000,temp_poll);
  var extrudertemp = (ComboBoxEntry) builder.get_object("extrudertemp");
  var list_store = new Gtk.ListStore(1,typeof(string));
  extrudertemp.set_model(list_store);
  extrudertemp.set_text_column(0);
  string[] extemp = {"0", "180","190","200", "230", "240", "250"};
  int i;
  for(i = 0 ; i < extemp.length; i++) {
    extrudertemp.append_text(extemp[i]);
  }
  list_store = new Gtk.ListStore(1,typeof(string));
  var bedtemp = (ComboBoxEntry) builder.get_object("bedtemp");
  bedtemp.set_model(list_store);
  bedtemp.set_text_column(0);
  string[] btemp = {"0","40",
		  "45","50","55","60","65","70","75","80","85","90","95","100","105" };
  for(i = 0 ; i < btemp.length ; i++) {
    bedtemp.append_text(btemp[i]);
  }
 
  var fenster = (Widget) builder.get_object("window1");
  fenster.show_all();
  Gtk.main();
  return 0;
}
