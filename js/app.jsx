import React from "react";
import ReactDOM from "react-dom";
import "bootstrap";
import { BAMViewer } from "alignment.js";

import ErrorCorrection from "./error_correction.jsx";
import SuperReadGraph from "./super_read_graph.jsx";
import HaplotypeReconstruction from "./haplotype_reconstruction.jsx";

import "./bootstrap.min.css";
require("../node_modules/alignment.js/lib/alignment.css");


function Link(props) {
  return (<li
    className={props.active ? "nav-item active" : "nav-item"}
    onClick={props.onClick}
  >
    <a className="nav-link">{props.text}<span class="sr-only">(current)</span></a>
  </li>);
}

function Dropdown(props) {
  return (<ul className="navbar-nav ">
    <li className="nav-item dropdown">
      <a
        className="nav-link dropdown-toggle"
        href="#"
        id="navbarDropdown"
        role="button"
        data-toggle="dropdown"
        aria-haspopup="true"
        aria-expanded="false"
      >
        {props.title}
      </a>
      <div className="dropdown-menu" aria-labelledby="navbarDropdown">
        {props.children}
      </div>
    </li>
  </ul>);
}

function Navbar(props) {
  return (<nav className="navbar navbar-expand-lg navbar-dark bg-primary">
    <a className="navbar-brand" href="#">ACME Haplotype Reconstruction</a>
    <div class="collapse navbar-collapse" id="navbarColor01">
      <ul class="navbar-nav mr-auto">
        {props.children}
      </ul>
    </div>
  </nav>);
}

class App extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      viewing: 'mapped-reads'
    }
  }
  render() {
    return (<div>
      <Navbar>
        <Link
          active={this.state.viewing == 'mapped-reads'}
          text="Mapped Reads"
          onClick={() => this.setState({viewing: 'mapped-reads'})}
        />
        <Link
          active={this.state.viewing == 'error-correction'}
          text="Error Correction"
          onClick={() => this.setState({viewing: 'error-correction'})}
        />
        <Link
          active={this.state.viewing == 'read-graph'}
          text="Super Read Graph"
          onClick={() => this.setState({viewing: 'super-read-graph'})}
        />
        <Link
          active={this.state.viewing == 'haplotype-reconstruction'}
          text="Haplotype Reconstruction"
          onClick={() => this.setState({viewing: 'haplotype-reconstruction'})}
        />
      </Navbar>
      <div style={{ maxWidth: 1140 }} className="container-fluid">
        {this.state.viewing == 'mapped-reads' && <BAMViewer data_url="sorted.bam" />}
        {this.state.viewing == 'error-correction' && <ErrorCorrection />}
        {this.state.viewing == 'super-read-graph' && <SuperReadGraph />}
        {this.state.viewing == 'haplotype-reconstruction' && <HaplotypeReconstruction />}
      </div>
    </div>);
  }
}

ReactDOM.render(
  <App />,
  document.body.appendChild(document.createElement("div"))
);
