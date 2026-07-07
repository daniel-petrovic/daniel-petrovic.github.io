---
title: Services & Experience
description: Embedded C++ consulting services — Yocto, Qt6, OPC UA, modern C++ for industrial and medical systems.
permalink: /cv/
---

<section class="panel">
  <p class="eyebrow">Senior Embedded Linux &amp; Modern C++ Consultant</p>
  <h1>Daniel Petrovic</h1>
  <p class="lead">
    Building robust Linux-based embedded software for complex products and platforms.
  </p>

  <div class="grid-two">
    <article class="card">
      <h2>Contact</h2>
      <ul class="plain-list">
        <li><strong>Location:</strong> Bregenz, Austria</li>
        <li><strong>Telephone:</strong> +43 677 615 948 84</li>
        <li><strong>Email:</strong> <a href="mailto:contact@petrovich.ch">contact@petrovich.ch</a></li>
        <li><strong>LinkedIn:</strong> <a href="https://www.linkedin.com/in/daniel-petrovic/">linkedin.com/in/daniel-petrovic</a></li>
      </ul>
    </article>

    <article class="card">
      <h2>Availability</h2>
      <p>Currently employed. Ready for freelance engagements roughly September/October 2026.</p>
    </article>
  </div>
</section>

<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Services</p>
      <h2>What I offer</h2>
    </div>
  </div>
  <div class="card-grid">
    <article class="card">
      <h3>Embedded Linux &amp; Yocto</h3>
      <p>BSP integration, Yocto layer development, kernel configuration, and platform build system setup for ARM/Linux devices.</p>
    </article>
    <article class="card">
      <h3>Modern C++ Development</h3>
      <p>C++17/20/23 application development with focus on clean architecture, performance, and maintainability for embedded and desktop targets.</p>
    </article>
    <article class="card">
      <h3>Qt6 &amp; QML</h3>
      <p>Application framework design, Qt6/QML UI implementation, embedded GUI optimization, and cross-platform deployment.</p>
    </article>
    <article class="card">
      <h3>Industrial Protocols</h3>
      <p>OPC UA server/client integration, CAN/CANopen communication, PLC interfacing (Siemens S7), and IoT connectivity (Azure IoT).</p>
    </article>
    <article class="card">
      <h3>Software Architecture &amp; Technical Lead</h3>
      <p>Modular architecture design, design pattern application, code quality tooling (Clang-tidy, custom matchers), and technical strategy. Technical leadership and mentoring for embedded teams.</p>
    </article>
    <article class="card">
      <h3>Performance Optimization</h3>
      <p>Profiling, benchmarking, and optimization of embedded applications. Real-time constraint analysis, memory footprint reduction, and throughput improvements using sanitizers, heaptrack, valgrind, and custom tooling.</p>
    </article>
    <article class="card">
      <h3>Build Systems &amp; CI/CD</h3>
      <p>Yocto/OpenEmbedded optimization, CMake/Meson build system design, Azure DevOps and GitHub Actions pipeline setup, and cross-compilation toolchain configuration.</p>
    </article>
    <article class="card">
      <h3>Legacy Modernization</h3>
      <p>Porting legacy codebases, migrating to modern C++ standards, updating build systems, and improving test coverage.</p>
    </article>
  </div>
</section>

<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Technologies</p>
      <h2>Tools &amp; platforms</h2>
    </div>
  </div>
  <ul class="tag-list">
    <li>C++17/20/23</li>
    <li>Qt6 / QML</li>
    <li>Yocto / OpenEmbedded</li>
    <li>Linux (Embedded &amp; Desktop)</li>
    <li>OPC UA</li>
    <li>CAN / CANopen</li>
    <li>ARM Cortex-A</li>
    <li>CMake / Meson</li>
    <li>Clang / LLVM</li>
    <li>Azure IoT</li>
    <li>Mender OTA</li>
    <li>Docker</li>
    <li>Python</li>
    <li>Git / Azure DevOps</li>
  </ul>
</section>

<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Case studies</p>
      <h2>How I've helped</h2>
    </div>
  </div>

  <article class="cv-item">
    <p class="post-meta">2022 &mdash; Present</p>
    <h3>Embedded Software for Dental Lab Equipment &amp; CNC Milling</h3>
    <p><strong>EBCONT group GmbH, Austria</strong></p>
    <p>Led a small team maintaining and supporting a customer's legacy Windows 7 Compact Embedded devices before porting the entire software stack to Yocto Linux. Designed and implemented a modular next-generation application framework reusable across different product families. The initial target were Avnet evaluation boards (MSC E5 and E1) with i.MX8 MPlus and i.MX8 QuadMax SoMs (Cortex-A53/A72) running Yocto Linux, before moving to a custom board developed in-house for the final dental lab equipment. Integrated CNC control for a 5-axis milling (dry) device on a realtime Linux kernel with strict timing requirements — multiple CNC kernel callbacks running at 2ms intervals. Developed an OPC UA server enabling automated production testing, reducing manual manufacturing effort and improving test reliability. Integrated CAN, EEPROM (I2C), and RFID for device control. Implemented OTA updates via Mender and Azure IoT connectivity for remote device management. Contributed Qt6/QML UI components and helped establish C++ coding guidelines for the team. Optimized Azure DevOps CI/CD pipelines, reducing build times by over 40% and helping the team meet critical project deadlines. Diagnosed and resolved issues across the software stack — OS networking, GStreamer pipeline problems, memory leaks, and threading bugs — using address sanitizer, thread sanitizer, heaptrack, valgrind, and custom-built tools — standard sanitizers were of limited use due to the project's realtime constraints.</p>
    <p class="post-meta"><strong>Impact:</strong> Supporting production of hundreds of dental lab devices worldwide.</p>
  </article>

  <article class="cv-item">
    <p class="post-meta">2017 &mdash; 2022</p>
    <h3>Simulation &amp; PLC Communication for Warehouse Management</h3>
    <p><strong>LTW Intralogistics GmbH, Austria</strong></p>
    <p>Built simulation environments and controlling services for Siemens S7 PLCs (stacker cranes, conveyor systems) in C++/MFC and C#/WPF for automated warehouse management systems running on Windows hosts. Implemented ISO TCP/RFC1006 communication protocols for PLC control. Developed diagnostic tools and ported legacy codebases to modern infrastructure. Programmed T-SQL database components (transactions, stored procedures) for warehouse storage. Implemented C# services for SAP warehouse host integration. Provided on-site support during installation and integration phases at customer facilities.</p>
    <p class="post-meta"><strong>Impact:</strong> Simulation and control software for automated warehouses managing thousands of storage locations.</p>
  </article>

  <article class="cv-item">
    <p class="post-meta">2013 &mdash; 2017</p>
    <h3>Numerical Simulation Tooling for Industrial Biomass Systems</h3>
    <p><strong>Viessmann GmbH, Austria</strong></p>
    <p>Developed C++/Qt/Python applications for thermochemical and fluid-dynamic calculations used in industrial biomass furnace design. Contributed to EU research projects in collaboration with academic research institutes. Built tools to support sales engineering with calculation and dimensioning workflows.</p>
    <p class="post-meta"><strong>Impact:</strong> Improved efficiency and reduced emissions across multiple industrial biomass plants in Europe.</p>
  </article>
</section>

<section class="panel">
  <h2>Earlier Experience</h2>
  <ul>
    <li><strong>Fullstack Developer</strong> &mdash; Eyeworkers Interactive GmbH, Karlsruhe (2012&ndash;2013): PHP/NodeJS/MySQL backend, HTML/CSS/JS frontend, unit testing.</li>
    <li><strong>Freelance Work</strong> &mdash; Germany (2017): PHP/WordPress plugins, Java data tools.</li>
    <li><strong>University &amp; Contractor Projects</strong> &mdash; Germany (2005&ndash;2012): CFD simulations in C++/OpenFOAM with VTK visualization, numerical computation, web development with Python/Django and PHP.</li>
  </ul>
</section>

<section class="panel">
  <h2>Education</h2>
  <ul>
    <li><strong>Diplom-Ingenieur, Chemical Engineering</strong> &mdash; Karlsruhe Institute of Technology (KIT), Germany, 2013</li>
    <li><strong>Part-time Bachelor of Mathematics</strong> &mdash; Fernuniversität Hagen, currently attending</li>
  </ul>
</section>

<section class="panel">
  <h2>Certifications</h2>
  <ul>
    <li><strong>Certificate of Excellence</strong> - OpenCV University, 2024, for outstanding performance in the OpenCV Bootcamp</li>
    <li><strong>Structuring Machine Learning Projects</strong>, Coursera, 2020</li>
    <li><strong>Improving Deep Neural Networks: Hyperparameter Tuning, Regularization and Optimization</strong>, Coursera, 2020</li>
    <li><strong>Neural Networks and Deep Learning</strong>, Coursera, 2020</li>
    <li><strong>Machine Learning</strong>, Coursera, 2020</li>
    <li><strong>Certified Professional for Software Architecture</strong>, iSAQB, 2019</li>
    <li><strong>C++ Certified Professional Programmer</strong>, C++ Institute, 2017</li>
    <li><strong>C++ Certified Associate Programmer</strong>, C++ Institute, 2017</li>
  </ul>
</section>
